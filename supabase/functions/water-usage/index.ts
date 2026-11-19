import { rpcOf, userClient, verifiedClaims } from '../_shared/deno.ts';
import { jsonHandler } from '../_shared/http.js';
import { createWaterUsage } from '../_shared/water-usage.js';

const fail = (status: number, code: string, message: string) =>
  Object.assign(new Error(message), { status, code });

async function authorize(req: Request, roomNo: string) {
  const authorization = req.headers.get('Authorization') ?? '';
  if (!/^Bearer\s+\S+$/i.test(authorization) || !(await verifiedClaims(authorization)).userId) {
    throw fail(401, 'unauthenticated', 'กรุณาเข้าสู่ระบบอีกครั้ง');
  }

  const caller = userClient(authorization);
  if (await rpcOf(caller)('is_admin') !== true) {
    throw fail(403, 'permission-denied', 'สำหรับผู้ดูแลที่ยืนยันตัวตนแล้ว');
  }

  const { data, error } = await caller.from('rooms')
    .select('room_no').eq('room_no', roomNo).eq('active', true).maybeSingle();
  if (error) throw new Error('Could not check access to water meter room');
  if (!data) throw fail(404, 'not-found', 'ไม่พบห้องพักที่เปิดใช้งาน');
}

Deno.serve(jsonHandler(createWaterUsage({
  authorize,
  getConfig: () => ({
    baseUrl: Deno.env.get('THINGSBOARD_BASE_URL'),
    readKey: Deno.env.get('THINGSBOARD_READ_API_KEY'),
    roomDevices: Deno.env.get('THINGSBOARD_ROOM_DEVICES'),
    staleAfterSeconds: Deno.env.get('THINGSBOARD_STALE_AFTER_SECONDS'),
  }),
})));
