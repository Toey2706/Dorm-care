/**
 * ประมวลผลเหตุการณ์จาก LINE (ฝั่งผู้พัก)
 *
 * ทุกอย่างที่แตะบริการภายนอกถูกส่งเข้ามา (rpc, storage) จึงทดสอบด้วยของจำลองได้
 *
 * หลักการกันข้อมูลหาย:
 * - บันทึกว่าเหตุการณ์ "ทำเสร็จแล้ว" หลังประมวลผลสำเร็จเท่านั้น ถ้าพังกลางทาง webhook ตอบ 500
 *   และ LINE ส่งซ้ำได้ (ถ้าเปิด Webhook redelivery)
 * - บันทึกสถานะบทสนทนาแบบตรวจเวอร์ชัน ถ้ามีเหตุการณ์อื่นเขียนก่อน อ่านใหม่แล้วคำนวณใหม่
 * - รหัสใบงานคำนวณจากร่าง (ผู้พัก + เวลาเริ่มแจ้ง) กดยืนยันซ้ำจึงได้ใบเดิม
 * - เก็บรูปให้ครบก่อนสร้างใบงาน ถ้าดึงรูปไม่ได้ ไม่สร้างใบงาน และร่างยังอยู่ให้กดยืนยันใหม่
 */

import * as conversation from './conversation.js';
import * as M from './messages.js';
import { statusLabel, thaiDateTime } from './format.js';
import { sha256Hex } from './line.js';

const SAVE_RETRIES = 3;

export const ticketIdFor = async (userId, draft) => `r_${(await sha256Hex(`${userId}:${draft.startedAt}`)).slice(0, 24)}`;

const categoryLabel = (code) => (conversation.CATEGORIES.find((c) => c.code === code) || { label: code }).label;

function toConversationEvent(event) {
  const at = typeof event.timestamp === 'number' ? event.timestamp : 0;
  if (event.type === 'follow') return { kind: 'follow', at };
  if (event.type !== 'message') return null;
  if (event.message.type === 'text') return { kind: 'text', text: event.message.text, at };
  if (event.message.type === 'image') return { kind: 'image', messageId: event.message.id, at };
  return { kind: 'text', text: '', at };
}

/**
 * @param {object} deps
 * @param {(fn:string, args?:object)=>Promise<any>} deps.rpc  เรียกฟังก์ชันในฐานข้อมูลด้วยสิทธิ์ service_role
 * @param {{save:(path:string, bytes:Uint8Array, contentType:string)=>Promise<void>}} deps.storage  bucket resident-photos
 * @param {{warn:Function, error:Function}} deps.logger
 */
export function createWebhook({ rpc, storage, logger }) {
  const setIdle = (userId) => rpc('line_set_idle', { p_user_id: userId });

  async function loadContext(userId) {
    const ctx = await rpc('line_context', { p_user_id: userId });
    const b = ctx && ctx.binding;
    return {
      session: ctx && ctx.session,
      binding: b ? { status: b.status, roomNo: b.room_no, displayName: b.display_name } : null,
    };
  }

  /** คำนวณสถานะใหม่แล้วบันทึก ถ้าเวอร์ชันชนก็อ่านใหม่ */
  async function advance(userId, convEvent) {
    for (let i = 0; i < SAVE_RETRIES; i += 1) {
      const { session, binding } = await loadContext(userId);
      const r = conversation.handle(session, binding, convEvent);
      const saved = await rpc('line_save_session', {
        p_user_id: userId,
        p_version: session ? session.version : null,
        p_state: r.session.state,
        p_draft: r.session.draft,
      });
      if (saved) return { ...r, binding };
    }
    throw new Error('line session busy');
  }

  /** คืนข้อความที่จะตอบกลับสำหรับเหตุการณ์ 1 รายการ */
  async function handleEvent(client, event) {
    const userId = event.source && event.source.userId;
    if (!userId || (event.source.type && event.source.type !== 'user')) return [];
    const convEvent = toConversationEvent(event);
    if (!convEvent) return [];
    if (event.webhookEventId && (await rpc('line_is_processed', { p_event_id: event.webhookEventId }))) return [];

    const { effects, binding } = await advance(userId, convEvent);

    const replies = [];
    for (const effect of effects) {
      if (effect.type === 'reply') replies.push(...effect.messages);
      if (effect.type === 'showStatus') replies.push(await statusMessage(binding.roomNo));
      if (effect.type === 'showContact') replies.push(M.contact(await rpc('line_contact_text')));
      if (effect.type === 'redeemCode') replies.push(await redeemCode(client, userId, effect.code));
      if (effect.type === 'createTicket') replies.push(await submitReport(client, userId, effect.draft));
    }
    if (event.webhookEventId) await rpc('line_mark_processed', { p_event_id: event.webhookEventId });
    return replies;
  }

  async function statusMessage(roomNo) {
    const rows = (await rpc('line_recent_tickets', { p_room_no: roomNo })) || [];
    return M.statusList(
      rows.map((t) => ({
        ticketNo: t.ticket_no,
        categoryLabel: categoryLabel(t.category),
        statusLabel: statusLabel(t.status, t.assigned),
        createdAtText: t.created_at ? thaiDateTime(new Date(t.created_at)) : '-',
      }))
    );
  }

  /** ถูกต้อง: ผูกห้องทันที, ผิด: ยังอยู่ขั้นรอรหัสให้พิมพ์ใหม่ได้ */
  async function redeemCode(client, userId, code) {
    const profile = await client.getProfile(userId).catch(() => null);
    const r = await rpc('line_redeem_code', {
      p_user_id: userId,
      p_code: code,
      p_display_name: (profile && profile.displayName) || '',
    });
    if (r.result === 'BOUND') {
      await setIdle(userId);
      return M.bindingDone(r.room_no);
    }
    if (r.result === 'ALREADY') {
      await setIdle(userId);
      return M.text('บัญชีนี้ผูกห้องไว้แล้ว หากต้องการเปลี่ยนห้อง กรุณาติดต่อผู้ดูแล');
    }
    if (r.result === 'LIMIT') {
      await setIdle(userId);
      return M.text('ใส่รหัสผิดหลายครั้งเกินไป กรุณาลองใหม่พรุ่งนี้ หรือติดต่อผู้ดูแล');
    }
    return M.bindCodeInvalid();
  }

  async function submitReport(client, userId, draft) {
    try {
      const ticketId = await ticketIdFor(userId, draft);
      let r;
      const existingNo = await rpc('line_ticket_no', { p_ticket_id: ticketId });
      if (existingNo) {
        r = await rpc('line_create_ticket', { p_ticket_id: ticketId, p_user_id: userId, p_category: draft.category, p_description: draft.description });
      } else {
        const photoPaths = await savePhotos(client, ticketId, draft.photoMessageIds || []);
        r = await rpc('line_create_ticket', {
          p_ticket_id: ticketId,
          p_user_id: userId,
          p_category: draft.category,
          p_description: draft.description,
          p_photo_paths: photoPaths,
        });
      }
      if (r.error === 'NOT_BOUND') {
        await setIdle(userId);
        return M.text('บัญชีนี้ยังไม่ได้ผูกห้องที่ใช้งานอยู่ จึงส่งแจ้งซ่อมไม่ได้ กรุณาติดต่อผู้ดูแล');
      }
      await setIdle(userId);
      return M.ticketCreated(r.ticket_no, r.room_no);
    } catch (err) {
      logger.error('submitReport failed', { userId, error: err.message });
      return M.reportFailed();
    }
  }

  /** ดึงรูปจาก LINE ไปเก็บให้ครบทุกรูป รูปไหนไม่สำเร็จ ล้มทั้งรายการ */
  async function savePhotos(client, ticketId, messageIds) {
    const paths = [];
    for (const [i, messageId] of messageIds.entries()) {
      const { bytes, contentType } = await client.getContent(messageId);
      const path = `${ticketId}/${i + 1}.jpg`;
      await storage.save(path, bytes, contentType);
      paths.push(path);
    }
    return paths;
  }

  /** คืน true ถ้าทุกเหตุการณ์สำเร็จ (false = ให้ webhook ตอบ 500) */
  async function handleAll(client, events) {
    let allOk = true;
    for (const event of events) {
      try {
        const replies = await handleEvent(client, event);
        if (replies.length && event.replyToken) {
          await client.reply(event.replyToken, replies).catch((err) => logger.warn('reply failed', { error: err.message }));
        }
      } catch (err) {
        allOk = false;
        logger.error('handleEvent failed', { error: err.message, type: event.type });
      }
    }
    return allOk;
  }

  return { handleAll, handleEvent };
}
