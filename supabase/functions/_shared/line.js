// ใช้ Web Crypto และ fetch เท่านั้น จึงรันได้ทั้งบน Deno (Edge Functions) และ Node (ตอนทดสอบ)

const API = 'https://api.line.me/v2/bot';
const DATA_API = 'https://api-data.line.me/v2/bot';

const encoder = new TextEncoder();

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(String(value)));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function toBase64(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

/** ตรวจ x-line-signature (HMAC-SHA256 ของ body ดิบด้วย Channel Secret) */
export async function verifySignature(rawBody, signature, channelSecret) {
  if (!rawBody || !signature || !channelSecret) return false;
  const key = await crypto.subtle.importKey('raw', encoder.encode(channelSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const body = typeof rawBody === 'string' ? encoder.encode(rawBody) : rawBody;
  const expected = toBase64(new Uint8Array(await crypto.subtle.sign('HMAC', key, body)));
  const given = String(signature);
  if (expected.length !== given.length) return false;
  // เทียบครบทุกตัวอักษร ไม่หยุดที่ตัวแรกที่ต่าง เวลาตอบจึงไม่บอกว่าลายเซ็นถูกไปกี่ตัว
  let diff = 0;
  for (let i = 0; i < expected.length; i += 1) diff |= expected.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

export function createClient(accessToken, fetchImpl = fetch) {
  async function call(url, body, extraHeaders = {}) {
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}`, ...extraHeaders },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      const err = new Error(`LINE API ${res.status}: ${detail}`);
      err.status = res.status;
      throw err;
    }
  }

  return {
    reply: (replyToken, messages) => call(`${API}/message/reply`, { replyToken, messages: messages.slice(0, 5) }),
    /**
     * retryKey (UUID) ทำให้ LINE ไม่ส่งซ้ำเมื่อเรียกซ้ำด้วยคีย์เดิม
     * ถ้าคีย์เดิมเคยส่งสำเร็จแล้ว LINE ตอบ 409 ซึ่งถือว่าส่งแล้ว
     */
    async push(to, messages, retryKey) {
      try {
        await call(`${API}/message/push`, { to, messages: messages.slice(0, 5) }, retryKey ? { 'X-Line-Retry-Key': retryKey } : {});
        return { alreadySent: false };
      } catch (err) {
        if (retryKey && err.status === 409) return { alreadySent: true };
        throw err;
      }
    },
    async getProfile(userId) {
      const res = await fetchImpl(`${API}/profile/${encodeURIComponent(userId)}`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!res.ok) return null;
      return res.json();
    },
    async getContent(messageId) {
      const res = await fetchImpl(`${DATA_API}/message/${encodeURIComponent(messageId)}/content`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!res.ok) throw new Error(`LINE content ${res.status}`);
      return {
        bytes: new Uint8Array(await res.arrayBuffer()),
        contentType: res.headers.get('content-type') || 'image/jpeg',
      };
    },
  };
}
