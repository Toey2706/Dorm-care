// แอปเรียกหลังมอบหมายงานหรือหลังช่างบันทึกผล เพื่อเด้งแจ้งเตือนเข้าแอป Android ของคนที่เกี่ยวข้อง
// ตรวจสิทธิ์ผู้เรียกด้วยฟังก์ชันในฐานข้อมูล (is_admin / is_staff) แล้วอ่านใบงานจริงเอง ไม่เชื่อข้อมูลที่แอปส่งมา
import { jsonHandler } from '../_shared/http.js';
import { staffMessage } from '../_shared/fcm.js';
import { rpcOf, serviceClient, userClient } from '../_shared/deno.ts';
import { staffPush } from '../_shared/staff-push.ts';

const fail = (status: number, code: string, message: string) => Object.assign(new Error(message), { status, code });

Deno.serve(
  jsonHandler(async (body: { kind?: string; ticket_id?: string }, req: Request) => {
    const asCaller = rpcOf(userClient(req.headers.get('Authorization') ?? ''));
    const kind = body.kind;
    if (kind !== 'assigned' && kind !== 'completed') throw fail(400, 'invalid-argument', 'ไม่รู้จักเหตุการณ์นี้');
    if (!body.ticket_id) throw fail(400, 'invalid-argument', 'ไม่มีเลขใบงาน');

    const allowed = await asCaller(kind === 'assigned' ? 'is_admin' : 'is_staff');
    if (allowed !== true) throw fail(403, 'permission-denied', 'ไม่มีสิทธิ์');

    const db = serviceClient();
    const { data: t, error } = await db.from('tickets').select('id, ticket_no, room_no, category, status, assigned_to').eq('id', body.ticket_id).single();
    if (error || !t) throw fail(404, 'not-found', 'ไม่พบใบงาน');

    const push = staffPush(db);
    if (kind === 'assigned') {
      if (!t.assigned_to) return { sent: 0 };
      return push.toUsers([t.assigned_to], staffMessage('assigned', t));
    }
    if (t.status !== 'COMPLETED') return { sent: 0 };
    return push.toAdmins(staffMessage('completed', t));
  })
);
