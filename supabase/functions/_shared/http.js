// แอป Flutter บนมือถือไม่ต้องใช้ CORS แต่ตอนทดสอบด้วย flutter run -d chrome ต้องมี
export const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export const json = (status, body) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' } });

/** ห่อ handler ที่รับ body JSON: จัดการ OPTIONS, แปลง error ที่มี status เป็นคำตอบ, ที่เหลือเป็น 500 */
export function jsonHandler(fn) {
  return async (req) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
    if (req.method !== 'POST') return json(405, { error: 'method-not-allowed' });
    let body;
    try {
      body = await req.json();
    } catch {
      return json(400, { error: 'invalid-json', message: 'ข้อมูลไม่ถูกต้อง' });
    }
    try {
      return json(200, await fn(body, req));
    } catch (err) {
      if (err.status) return json(err.status, { error: err.code || 'error', message: err.message, ...(err.extra || {}) });
      console.error(err);
      return json(500, { error: 'internal', message: 'เกิดข้อผิดพลาด กรุณาลองใหม่' });
    }
  };
}
