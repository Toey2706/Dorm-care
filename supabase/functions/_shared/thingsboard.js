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

  async function telemetry(deviceId, keys) {
    if (!token || Date.now() - tokenAt > 10 * 60_000) await login();
    const url = `${base}/api/plugins/telemetry/DEVICE/${encodeURIComponent(deviceId)}/values/timeseries?keys=${keys.join(',')}`;
    let res = await fetch(url, { headers: { 'X-Authorization': `Bearer ${token}` } });
    if (res.status === 401) {
      await login();
      res = await fetch(url, { headers: { 'X-Authorization': `Bearer ${token}` } });
    }
    if (!res.ok) throw Object.assign(new Error(`thingsboard telemetry ${res.status}`), { status: 502 });
    return res.json();
  }

  return { telemetry };
}
