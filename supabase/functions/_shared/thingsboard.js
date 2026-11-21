export function thingsboard({ base = 'https://thingsboard.cloud', publicId, fetch = globalThis.fetch }) {
  let token = null;
  let tokenAt = 0;

  async function login() {
    const res = await fetch(`${base}/api/auth/login/public`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ publicId }),
    });
    if (!res.ok) throw Object.assign(new Error(`thingsboard login ${res.status}`), { status: 502 });
    token = (await res.json()).token;
    tokenAt = Date.now();
  }

  async function get(url) {
    if (!token || Date.now() - tokenAt > 10 * 60_000) await login();
    let res = await fetch(url, { headers: { 'X-Authorization': `Bearer ${token}` } });
    if (res.status === 401) {
      await login();
      res = await fetch(url, { headers: { 'X-Authorization': `Bearer ${token}` } });
    }
    if (!res.ok) throw Object.assign(new Error(`thingsboard telemetry ${res.status}`), { status: 502 });
    return res.json();
  }

  const series = (deviceId) => `${base}/api/plugins/telemetry/DEVICE/${encodeURIComponent(deviceId)}/values/timeseries`;

  const telemetry = (deviceId, keys) => get(`${series(deviceId)}?keys=${keys.join(',')}`);

  async function sum(deviceId, key, startTs, endTs) {
    const interval = Math.max(1, endTs - startTs);
    const data = await get(`${series(deviceId)}?keys=${key}&startTs=${startTs}&endTs=${endTs}&agg=SUM&interval=${interval}&limit=1`);
    const total = (data[key] || []).reduce((acc, p) => acc + (Number(p.value) || 0), 0);
    return Math.round(total * 10) / 10;
  }

  return { telemetry, sum };
}
