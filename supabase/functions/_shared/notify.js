/**
 * ผู้ดูแลสั่งแจ้งผลซ่อมถึงผู้พักทาง LINE
 *
 * แอปสร้าง requestId (UUID) ใหม่ทุกครั้งที่ผู้ดูแลกดแจ้งผล ถ้าเน็ตหลุดแล้วแอปลองใหม่ด้วย requestId เดิม
 * ข้อความจะไม่ซ้ำ เพราะใช้เป็นทั้งรหัสบันทึกในฐานข้อมูลและ X-Line-Retry-Key
 * ถ้า LINE รับข้อความแล้ว จะไม่รายงานว่าล้มเหลว แม้บันทึกหลังส่งจะมีปัญหา
 */

import { CATEGORIES } from './conversation.js';
import * as M from './messages.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const categoryLabel = (code) => (CATEGORIES.find((c) => c.code === code) || { label: code }).label;

export class NotifyError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * @param {(fn:string, args?:object)=>Promise<any>} rpc  เรียกด้วย JWT ของผู้ดูแล ฐานข้อมูลตรวจสิทธิ์เอง
 */
export async function notifyResident({ rpc, client, logger }, { ticketId, requestId }) {
  if (!UUID.test(String(requestId || ''))) throw new NotifyError(400, 'รหัสคำขอไม่ถูกต้อง');
  if (!ticketId) throw new NotifyError(400, 'ไม่พบเลขใบแจ้งซ่อม');

  const begin = await rpc('begin_notify', { p_ticket_id: String(ticketId), p_request_id: requestId });
  if (begin.action === 'DUPLICATE') return { ok: true, duplicate: true };

  const t = begin.ticket;
  const message = M.repairResult({ ticketNo: t.ticket_no, roomNo: t.room_no, repairResult: t.repair_result }, categoryLabel(t.category));
  try {
    await client.push(t.line_user_id, [message], requestId);
  } catch (err) {
    await rpc('finish_notify', { p_request_id: requestId, p_ok: false, p_error: err.message }).catch(() => {});
    throw new NotifyError(503, 'ส่งข้อความ LINE ไม่สำเร็จ กรุณาลองใหม่');
  }

  try {
    await rpc('finish_notify', { p_request_id: requestId, p_ok: true });
    return { ok: true };
  } catch (err) {
    logger.error('LINE sent but logging failed', { ticketId, requestId, error: err.message });
    return { ok: true, logged: false };
  }
}
