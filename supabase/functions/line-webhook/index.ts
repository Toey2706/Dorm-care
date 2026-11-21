// ตั้งค่า verify_jwt = false (LINE ไม่มี JWT ของ Supabase) ความปลอดภัยมาจากลายเซ็น x-line-signature แทน
import { verifySignature, createClient as lineClient } from '../_shared/line.js';
import { createWebhook } from '../_shared/webhook.js';
import { ALIAS, richMenuApi } from '../_shared/richmenu.js';
import { env, logger, rpcOf, serviceClient } from '../_shared/deno.ts';
import { staffMessage } from '../_shared/fcm.js';
import { staffPush } from '../_shared/staff-push.ts';
import { thingsboard } from '../_shared/thingsboard.js';
import { waterUsage as usageFor } from '../_shared/water.js';

const db = serviceClient();
const menus = richMenuApi(env('LINE_CHANNEL_ACCESS_TOKEN'));
const tb = thingsboard({ publicId: Deno.env.get('TB_PUBLIC_ID') ?? '495be850-e42c-11f1-b8a1-9db681a717b8' });
const webhook = createWebhook({
  rpc: rpcOf(db),
  storage: {
    async save(path: string, bytes: Uint8Array, contentType: string) {
      const { error } = await db.storage.from('resident-photos').upload(path, bytes, { contentType, upsert: true });
      if (error) throw new Error(`storage ${error.message}`);
    },
  },
  logger,
  async waterUsage(roomNo: string) {
    const { data, error } = await db.from('water_devices').select('tb_device_id').eq('room_no', roomNo).eq('active', true).maybeSingle();
    if (error) throw error;
    if (!data?.tb_device_id) return null;
    return usageFor({ sum: tb.sum, daily: tb.daily, deviceId: data.tb_device_id, nowMs: Date.now() });
  },
  richMenu: {
    async toBound(userId: string) {
      const info = await rpcOf(db)('line_water_rules', { p_user_id: userId }).catch(() => null);
      const id = (info?.has_device && (await menus.aliasTarget(ALIAS.BOUND_WATER))) || (await menus.aliasTarget(ALIAS.BOUND));
      if (id) await menus.link(userId, id); // ยังไม่ได้รัน line-richmenu-setup ก็ข้ามไป
    },
    toDefault: (userId: string) => menus.unlink(userId),
  },
  // ส่งแจ้งเตือนหลังตอบผู้พักไปแล้วได้ waitUntil ให้ฟังก์ชันทำงานต่อจนส่งเสร็จ ผู้พักไม่ต้องรอ
  onTicketCreated(ticket: { id: string; ticket_no: string; room_no: string; category: string }) {
    const job = staffPush(db)
      .toAdmins(staffMessage('created', ticket))
      .catch((err: Error) => logger.warn('staff push failed', { error: err.message }));
    // @ts-ignore EdgeRuntime มีเฉพาะบน Supabase Edge Functions
    if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(job);
  },
});

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const raw = new Uint8Array(await req.arrayBuffer());
  if (!(await verifySignature(raw, req.headers.get('x-line-signature'), env('LINE_CHANNEL_SECRET')))) {
    return new Response('Invalid signature', { status: 401 });
  }
  const body = JSON.parse(new TextDecoder().decode(raw));
  const ok = await webhook.handleAll(lineClient(env('LINE_CHANNEL_ACCESS_TOKEN')), body.events || []);
  // 500 เมื่อมีเหตุการณ์ที่ทำไม่สำเร็จ ถ้าเปิด Webhook redelivery ใน LINE Console จะส่งซ้ำให้
  return new Response(ok ? 'OK' : 'Retry', { status: ok ? 200 : 500 });
});
