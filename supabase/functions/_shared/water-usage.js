const FLOW_KEY = 'flow_lpm';
const TOTAL_KEY = 'total_liters_since_boot';
const DEVICE_ID = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

function badUpstream() {
  return Object.assign(new Error('อ่านข้อมูลการใช้น้ำไม่ได้ในขณะนี้ กรุณาลองใหม่'), {
    status: 502,
    code: 'water-data-unavailable',
  });
}

function meterSettings(config, roomNo) {
  if (!config.roomDevices || !config.baseUrl || !config.readKey?.trim()) return null;
  const devices = JSON.parse(config.roomDevices);
  if (!devices || typeof devices !== 'object' || Array.isArray(devices)) throw badUpstream();
  if (!Object.hasOwn(devices, roomNo)) return null;

  const deviceId = devices[roomNo];
  const origin = new URL(config.baseUrl);
  const staleAfterSeconds = Number(config.staleAfterSeconds ?? 180);
  if (typeof deviceId !== 'string' || !DEVICE_ID.test(deviceId)
      || origin.protocol !== 'https:' || origin.username || origin.password
      || origin.pathname !== '/' || origin.search || origin.hash
      || !Number.isSafeInteger(staleAfterSeconds) || staleAfterSeconds <= 0) {
    throw badUpstream();
  }

  const url = new URL(`/api/plugins/telemetry/DEVICE/${deviceId}/values/timeseries`, origin);
  url.searchParams.set('keys', `${FLOW_KEY},${TOTAL_KEY}`);
  return { url, readKey: config.readKey.trim(), staleAfterSeconds };
}

function metricValue(point) {
  const value = point?.value;
  if (typeof value !== 'number' && (typeof value !== 'string' || value.trim() === '')) {
    throw badUpstream();
  }
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) throw badUpstream();
  return numeric;
}

function latestReading(data, now, staleAfterSeconds) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw badUpstream();
  const flow = data[FLOW_KEY]?.[0];
  const total = data[TOTAL_KEY]?.[0];
  if (flow === undefined || total === undefined) return { state: 'no_data' };

  const receivedAt = flow?.ts;
  if (!Number.isSafeInteger(receivedAt) || receivedAt <= 0
      || receivedAt !== total?.ts || receivedAt > now + 30000) {
    throw badUpstream();
  }
  return {
    state: 'ready',
    flow_lpm: metricValue(flow),
    total_liters_since_boot: metricValue(total),
    received_at_ms: receivedAt,
    stale: now - receivedAt > staleAfterSeconds * 1000,
  };
}

export function createWaterUsage({ authorize, getConfig, fetchImpl = fetch, now = Date.now }) {
  return async (body, req) => {
    const roomNo = typeof body?.room_no === 'string' ? body.room_no.trim() : '';
    if (!roomNo || roomNo.length > 80) {
      throw Object.assign(new Error('กรุณาเลือกห้องพัก'), { status: 400, code: 'invalid-argument' });
    }
    await authorize(req, roomNo);

    let reading;
    try {
      const meter = meterSettings(getConfig(), roomNo);
      if (!meter) return { state: 'unconfigured' };
      const response = await fetchImpl(meter.url, {
        headers: { Accept: 'application/json', 'X-Authorization': `ApiKey ${meter.readKey}` },
        redirect: 'error',
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) throw badUpstream();
      reading = latestReading(await response.json(), now(), meter.staleAfterSeconds);
    } catch {
      // Keep credentials and upstream response bodies out of the app and logs.
      throw badUpstream();
    }

    await authorize(req, roomNo);
    return reading;
  };
}
