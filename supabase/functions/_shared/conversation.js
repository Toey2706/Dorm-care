/**
 * บทสนทนาฝั่งผู้พักใน LINE (pure state machine)
 *
 * รับ: สถานะบทสนทนาเดิม + สถานะการผูกห้อง + เหตุการณ์จาก LINE
 * คืน: สถานะบทสนทนาใหม่ + รายการ effect ที่ webhook.js ต้องทำจริง
 *
 * effect ที่อาจล้มเหลว (redeemCode, createTicket) จะคงสถานะรอไว้ก่อน
 * webhook.js เปลี่ยนเป็น IDLE เมื่อทำสำเร็จเท่านั้น ข้อมูลที่ผู้พักกรอกจึงไม่หาย
 *
 * ปุ่ม Rich Menu ปัจจุบันตั้งเป็น action "ข้อความ" จึงรับเป็นข้อความตามชื่อปุ่ม
 * ผูกห้อง: ผู้ดูแลออกรหัส 6 หลักให้ผู้พัก ผู้พักพิมพ์รหัสใน LINE แล้วผูกห้องทันที
 */

import * as M from './messages.js';

export const COMMAND = Object.freeze({
  REPORT: 'แจ้งซ่อม',
  TRACK: 'ติดตามงาน',
  BIND: 'ผูกเลขห้อง',
  CONTACT: 'ติดต่อผู้ดูแล',
  CANCEL: 'ยกเลิก',
  SKIP: 'ข้าม',
  CONFIRM: 'ยืนยัน',
});

export const STATE = Object.freeze({
  IDLE: 'IDLE',
  BIND_WAIT_CODE: 'BIND_WAIT_CODE',
  REPORT_CATEGORY: 'REPORT_CATEGORY',
  REPORT_DETAIL: 'REPORT_DETAIL',
  REPORT_PHOTO: 'REPORT_PHOTO',
  REPORT_CONFIRM: 'REPORT_CONFIRM',
});

/** หมวดงานตาม Prototype (รหัสรอยืนยันกับ RPT-05 ใน Data Element Design) */
export const CATEGORIES = Object.freeze([
  { code: 'PLUMBING', label: 'ประปา' },
  { code: 'ELECTRICAL', label: 'ไฟฟ้า' },
  { code: 'AIRCON', label: 'เครื่องปรับอากาศ' },
  { code: 'FURNITURE', label: 'เฟอร์นิเจอร์' },
  { code: 'OTHER', label: 'อื่น ๆ' },
]);

export const MAX_PHOTOS = 3;
const MAX_DETAIL = 1000;
const CODE_PATTERN = /^[0-9]{6}$/;

const idle = () => ({ state: STATE.IDLE, draft: null });

function reply(...messages) {
  return { type: 'reply', messages };
}

function startReport(binding, startedAt) {
  if (!binding || binding.status !== 'ACTIVE') {
    return {
      session: { state: STATE.BIND_WAIT_CODE, draft: null },
      effects: [reply(M.text('ต้องผูกบัญชี LINE กับห้องพักก่อนแจ้งซ่อม'), M.askBindCode())],
    };
  }
  return {
    session: { state: STATE.REPORT_CATEGORY, draft: { startedAt, photoMessageIds: [] } },
    effects: [reply(M.askCategory(CATEGORIES))],
  };
}

function handleCommand(text, binding, startedAt) {
  switch (text) {
    case COMMAND.REPORT:
      return startReport(binding, startedAt);
    case COMMAND.TRACK:
      if (!binding || binding.status !== 'ACTIVE') {
        return { session: idle(), effects: [reply(M.text('ยังไม่ได้ผูกห้อง กด "ผูกเลขห้อง" ก่อนติดตามงาน'))] };
      }
      return { session: idle(), effects: [{ type: 'showStatus' }] };
    case COMMAND.BIND:
      if (binding && binding.status === 'ACTIVE') {
        return { session: idle(), effects: [reply(M.text(`บัญชีนี้ผูกกับห้อง ${binding.roomNo} แล้ว หากต้องการเปลี่ยนห้อง กรุณาติดต่อผู้ดูแล`))] };
      }
      return { session: { state: STATE.BIND_WAIT_CODE, draft: null }, effects: [reply(M.askBindCode())] };
    case COMMAND.CONTACT:
      return { session: idle(), effects: [{ type: 'showContact' }] };
    default:
      return null;
  }
}

/**
 * @param {{state:string, draft:object|null}|null} session
 * @param {{status:string, roomNo:string}|null} binding
 * @param {{kind:'text', text:string, at?:number}|{kind:'image', messageId:string, at?:number}|{kind:'follow'}} event
 *   at = เวลาของเหตุการณ์ (ms) ใช้เป็นรหัสร่างแจ้งซ่อม ทำให้กดยืนยันซ้ำแล้วไม่เกิดใบงานซ้ำ
 */
export function handle(session, binding, event) {
  const current = session && session.state ? session : idle();

  if (event.kind === 'follow') {
    return { session: idle(), effects: [reply(M.welcome())] };
  }

  const text = event.kind === 'text' ? String(event.text || '').trim() : null;

  if (text === COMMAND.CANCEL) {
    const wasBusy = current.state !== STATE.IDLE;
    return { session: idle(), effects: [reply(M.text(wasBusy ? 'ยกเลิกรายการแล้ว' : 'ไม่มีรายการที่ต้องยกเลิก'))] };
  }

  // ปุ่ม Rich Menu ขัดจังหวะได้ทุกขั้น
  if (text !== null) {
    const commandResult = handleCommand(text, binding, event.at || 0);
    if (commandResult) return commandResult;
  }

  switch (current.state) {
    case STATE.BIND_WAIT_CODE: {
      if (text === null) return { session: current, effects: [reply(M.askBindCode())] };
      const code = text.replace(/\s|-/g, '');
      if (!CODE_PATTERN.test(code)) {
        return { session: current, effects: [reply(M.text('รหัสต้องเป็นตัวเลข 6 หลักตามที่ได้รับจากผู้ดูแล กรุณาพิมพ์ใหม่'))] };
      }
      return { session: current, effects: [{ type: 'redeemCode', code }] };
    }

    case STATE.REPORT_CATEGORY: {
      const category = CATEGORIES.find((c) => c.label === text || c.code === text);
      if (!category) return { session: current, effects: [reply(M.askCategory(CATEGORIES))] };
      return {
        session: { state: STATE.REPORT_DETAIL, draft: { ...current.draft, category: category.code } },
        effects: [reply(M.text('กรุณาพิมพ์รายละเอียดปัญหา เช่น ตำแหน่งและอาการที่พบ\n(พิมพ์ "ยกเลิก" เพื่อยกเลิก)'))],
      };
    }

    case STATE.REPORT_DETAIL: {
      if (!text) return { session: current, effects: [reply(M.text('กรุณาพิมพ์รายละเอียดปัญหาเป็นข้อความ'))] };
      if (text.length > MAX_DETAIL) {
        return { session: current, effects: [reply(M.text(`รายละเอียดยาวเกิน ${MAX_DETAIL} ตัวอักษร กรุณาย่อให้สั้นลง`))] };
      }
      return {
        session: { state: STATE.REPORT_PHOTO, draft: { ...current.draft, description: text } },
        effects: [reply(M.askPhoto(MAX_PHOTOS))],
      };
    }

    case STATE.REPORT_PHOTO: {
      if (event.kind === 'image') {
        const existing = current.draft.photoMessageIds || [];
        if (existing.includes(event.messageId)) return { session: current, effects: [] }; // LINE ส่งเหตุการณ์ซ้ำ
        const ids = [...existing, event.messageId];
        const draft = { ...current.draft, photoMessageIds: ids };
        if (ids.length >= MAX_PHOTOS) {
          return { session: { state: STATE.REPORT_CONFIRM, draft }, effects: [reply(M.confirmReport(draft, CATEGORIES))] };
        }
        return { session: { state: STATE.REPORT_PHOTO, draft }, effects: [reply(M.photoReceived(ids.length, MAX_PHOTOS))] };
      }
      if (text === COMMAND.SKIP || text === 'เสร็จ') {
        return { session: { state: STATE.REPORT_CONFIRM, draft: current.draft }, effects: [reply(M.confirmReport(current.draft, CATEGORIES))] };
      }
      return { session: current, effects: [reply(M.askPhoto(MAX_PHOTOS))] };
    }

    case STATE.REPORT_CONFIRM: {
      if (text === COMMAND.CONFIRM) {
        return { session: current, effects: [{ type: 'createTicket', draft: current.draft }] };
      }
      return { session: current, effects: [reply(M.confirmReport(current.draft, CATEGORIES))] };
    }

    default:
      return { session: idle(), effects: [reply(M.help())] };
  }
}
