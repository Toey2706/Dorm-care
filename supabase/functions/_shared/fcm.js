// ส่งแจ้งเตือนเข้าแอป Android ผ่าน Firebase Cloud Messaging (HTTP v1)
// ใช้ Web Crypto กับ fetch เท่านั้น ทดสอบด้วย Node ได้ และไม่ต้องลง SDK ของ Google บน Edge Functions
import { CATEGORIES } from './conversation.js';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

function b64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem) {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** JWT ที่เซ็นด้วยกุญแจของ service account ใช้แลก access token จาก Google */
export async function signedAssertion(account, nowSeconds) {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({ iss: account.client_email, scope: FCM_SCOPE, aud: account.token_uri, iat: nowSeconds, exp: nowSeconds + 3600 })
  );
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(account.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(new Uint8Array(sig))}`;
}

export function createFcm(account, { fetchImpl = fetch, now = () => Date.now() } = {}) {
  let cached = null; // access token ใช้ได้ 1 ชั่วโมง เก็บไว้ใช้ซ้ำระหว่างที่ฟังก์ชันยังอุ่นอยู่

  async function accessToken() {
    if (cached && cached.expiresAt - 60_000 > now()) return cached.token;
    const assertion = await signedAssertion(account, Math.floor(now() / 1000));
    const res = await fetchImpl(account.token_uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
    });
    if (!res.ok) throw new Error(`google oauth ${res.status}: ${await res.text().catch(() => '')}`);
    const data = await res.json();
    cached = { token: data.access_token, expiresAt: now() + (data.expires_in || 3600) * 1000 };
    return cached.token;
  }

  /** คืน 'sent' หรือ 'invalid' (เครื่องถอนแอปหรือรหัสหมดอายุ ควรลบทิ้ง) ปัญหาอื่นโยน error */
  async function send(token, { title, body, data = {} }) {
    const res = await fetchImpl(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await accessToken()}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          // data ของ FCM ต้องเป็นข้อความทั้งหมด
          data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
          android: { priority: 'high' },
        },
      }),
    });
    if (res.ok) return 'sent';
    const text = await res.text().catch(() => '');
    if (res.status === 404 || text.includes('UNREGISTERED') || (res.status === 400 && text.includes('registration token'))) return 'invalid';
    throw new Error(`fcm ${res.status}: ${text}`);
  }

  return { send };
}

/**
 * ส่งถึงทุกเครื่องของรายชื่อพนักงาน ลบรหัสเครื่องที่ใช้ไม่ได้แล้ว
 * ส่งไม่สำเร็จบางเครื่องไม่ทำให้เครื่องอื่นพลาด
 */
export async function notifyStaff({ fcm, devices, removeDevices, logger }, userIds, message) {
  if (!fcm || userIds.length === 0) return { sent: 0, removed: 0, failed: 0 };
  const tokens = await devices(userIds);
  const invalid = [];
  let sent = 0;
  let failed = 0;
  await Promise.all(
    tokens.map(async (token) => {
      try {
        const r = await fcm.send(token, message);
        if (r === 'invalid') invalid.push(token);
        else sent += 1;
      } catch (err) {
        failed += 1;
        logger.warn('fcm send failed', { error: err.message });
      }
    })
  );
  if (invalid.length) await removeDevices(invalid);
  return { sent, removed: invalid.length, failed };
}

const CATEGORY = Object.fromEntries(CATEGORIES.map((c) => [c.code, c.label]));

/** ข้อความแจ้งเตือนแต่ละเหตุการณ์ data.ticket_id ให้แอปเปิดใบงานนั้นเมื่อกด */
export function staffMessage(kind, t) {
  const where = `ห้อง ${t.room_no} · ${CATEGORY[t.category] || t.category} · ${t.ticket_no}`;
  const data = { ticket_id: t.id, kind };
  if (kind === 'created') return { title: 'มีแจ้งซ่อมใหม่', body: where, data };
  if (kind === 'assigned') return { title: 'คุณได้รับมอบหมายงานใหม่', body: where, data };
  if (kind === 'completed') return { title: 'ช่างบันทึกผลแล้ว รอแจ้งผลทาง LINE', body: where, data };
  throw new Error(`unknown kind ${kind}`);
}
