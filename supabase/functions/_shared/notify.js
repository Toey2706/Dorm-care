/**
 * ผู้ดูแลสั่งแจ้งผลซ่อมถึงผู้พักทาง LINE
 *
 * แอปสร้าง requestId (UUID) ใหม่ทุกครั้งที่ผู้ดูแลกดแจ้งผล ถ้าเน็ตหลุดแล้วแอปลองใหม่ด้วย requestId เดิม
 * ข้อความจะไม่ซ้ำ เพราะใช้เป็นทั้งรหัสบันทึกในฐานข้อมูลและ X-Line-Retry-Key
 * ถ้า LINE รับข้อความแล้ว จะไม่รายงานว่าล้มเหลว แม้บันทึกหลังส่งจะมีปัญหา
 *
 * รูปหลังซ่อมส่งเป็นลิงก์ชั่วคราว (signed URL) เพราะ bucket เป็นแบบส่วนตัว ลิงก์หมดอายุแล้วรูปในแชตจะเปิดไม่ขึ้น
 * ถ้าสร้างลิงก์ไม่ได้ ยังส่งผลการซ่อมเป็นข้อความ เพราะผลการซ่อมสำคัญกว่ารูป
 */

import { CATEGORIES } from './conversation.js';
import * as M from './messages.js';

export const PHOTO_DAYS = 30;
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
 * @param {(ticketId:string, seconds:number)=>Promise<string[]>} photoUrls  ลิงก์รูปหลังซ่อมของงานนี้ ไม่เกิน 3 รูป
 */
export async function notifyResident({ rpc, client, logger, photoUrls }, { ticketId, requestId }) {
  if (!UUID.test(String(requestId || ''))) throw new NotifyError(400, 'รหัสคำขอไม่ถูกต้อง');
  if (!ticketId) throw new NotifyError(400, 'ไม่พบเลขใบแจ้งซ่อม');

  const begin = await rpc('begin_notify', { p_ticket_id: String(ticketId), p_request_id: requestId });
  if (begin.action === 'DUPLICATE') return { ok: true, duplicate: true };

  const t = begin.ticket;
  let urls = [];
  try {
    urls = (await photoUrls(String(ticketId), PHOTO_DAYS * 86400)).slice(0, 3);
  } catch (err) {
    logger.warn('photo links failed, sending text only', { ticketId, error: err.message });
  }
  const message = M.repairResult(
    { ticketNo: t.ticket_no, roomNo: t.room_no, repairResult: t.repair_result, photoCount: urls.length, photoDays: PHOTO_DAYS },
    categoryLabel(t.category)
  );
  try {
    // ส่งรวมใน push เดียว LINE นับโควตาเป็น 1 ข้อความต่อผู้รับ และ retry key เดียวกันกันส่งซ้ำได้ทั้งชุด
    await client.push(t.line_user_id, [message, ...urls.map(M.image)], requestId);
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
