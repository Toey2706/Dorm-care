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
  WATER: 'ตั้งแจ้งเตือนน้ำ',
  WATER_ADD: 'ตั้งเวลาแจ้งเตือน',
  WATER_CLEAR: 'ลบช่วงเวลาทั้งหมด',
  WATER_USAGE: 'ดูการใช้น้ำ',
});

export const STATE = Object.freeze({
  IDLE: 'IDLE',
  BIND_WAIT_CODE: 'BIND_WAIT_CODE',
  REPORT_CATEGORY: 'REPORT_CATEGORY',
  REPORT_DETAIL: 'REPORT_DETAIL',
  REPORT_PHOTO: 'REPORT_PHOTO',
  REPORT_CONFIRM: 'REPORT_CONFIRM',
  WATER_RULE: 'WATER_RULE',
  WATER_START: 'WATER_START',
  WATER_END: 'WATER_END',
  WATER_MINUTES: 'WATER_MINUTES',
});

export const WATER_MODE = Object.freeze({ WINDOW: 'เฉพาะช่วงเวลา', ALL_DAY: 'ทั้งวัน' });
export const WATER_MINUTE_CHOICES = Object.freeze([0.5, 1, 5, 10, 15, 20, 30, 60, 120]);
export const WATER_MINUTES_MIN = 0.5;
export const WATER_MINUTES_MAX = 180;
const validMinutes = (n) => Number.isFinite(n) && Number.isInteger(n * 2) && n >= WATER_MINUTES_MIN && n <= WATER_MINUTES_MAX;

export function parseDuration(input) {
  const t = String(input || '').trim();
  let m = /^(\d{1,3}(?:\.\d)?)(?:\s*นาที)?$/.exec(t);
  let n = m ? Number(m[1]) : null;
  if (n === null && (m = /^(\d{1,5})\s*วินาที$/.exec(t))) n = Number(m[1]) / 60;
  if (n === null && (m = /^(\d{1,3})\s*นาที\s*(\d{1,2})\s*วินาที$/.exec(t))) n = Number(m[1]) + Number(m[2]) / 60;
  return n !== null && validMinutes(n) ? n : null;
}

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

const RULE_PATTERN = /^(\d{1,2})[:.](\d{2})\s*(?:-|–|ถึง)\s*(\d{1,2})[:.](\d{2})\s+(.+)$/;

const DEFAULT_PATTERN = /^(?:ทั้งวัน|เวลาอื่น)\s*(\d.*)$/;

export function parseWaterRule(input) {
  const d = DEFAULT_PATTERN.exec(String(input || '').trim());
  if (d) {
    const minutes = parseDuration(d[1]);
    return minutes === null ? null : { allDay: true, minutes };
  }
  const m = RULE_PATTERN.exec(String(input || '').trim());
  if (!m) return null;
  const [h1, m1, h2, m2] = m.slice(1, 5).map(Number);
  const minutes = parseDuration(m[5]);
  if (h1 > 23 || h2 > 24 || m1 > 59 || m2 > 59 || (h2 === 24 && m2 > 0)) return null;
  const start = h1 * 60 + m1;
  const end = (h2 * 60 + m2) % 1440;
  if (start === end || minutes === null) return null;
  return { start, end, minutes };
}

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
    case COMMAND.WATER:
    case COMMAND.WATER_ADD:
    case COMMAND.WATER_CLEAR:
    case COMMAND.WATER_USAGE:
      if (!binding || binding.status !== 'ACTIVE') {
        return { session: idle(), effects: [reply(M.text('ยังไม่ได้ผูกห้อง กด "ผูกเลขห้อง" ก่อนตั้งแจ้งเตือนน้ำ'))] };
      }
      if (text === COMMAND.WATER) return { session: idle(), effects: [{ type: 'showWaterRules' }] };
      if (text === COMMAND.WATER_CLEAR) return { session: idle(), effects: [{ type: 'clearWaterRules' }] };
      if (text === COMMAND.WATER_USAGE) return { session: idle(), effects: [{ type: 'showWaterUsage' }] };
      return { session: { state: STATE.WATER_RULE, draft: null }, effects: [reply(M.askWaterMode())] };
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
const isBound = (binding) => Boolean(binding && binding.status === 'ACTIVE');

const TIME_PATTERN = /^(\d{2}):(\d{2})$/;
const toMinute = (time) => {
  const m = TIME_PATTERN.exec(String(time || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};
const minuteChoice = (text) => parseDuration(text);

function handleWater(current, text, event) {
  const typed = text ? parseWaterRule(text) : null;
  if (typed) return { session: current, effects: [{ type: 'addWaterRule', rule: typed }] };
  const draft = current.draft || {};
  const picked = event.kind === 'postback' ? toMinute(event.params && event.params.time) : null;

  switch (current.state) {
    case STATE.WATER_RULE:
      if (text === WATER_MODE.WINDOW) return { session: { state: STATE.WATER_START, draft: {} }, effects: [reply(M.askWaterTime('start'))] };
      if (text === WATER_MODE.ALL_DAY) {
        return { session: { state: STATE.WATER_MINUTES, draft: { allDay: true } }, effects: [reply(M.askWaterMinutes(null, WATER_MINUTE_CHOICES))] };
      }
      return { session: current, effects: [reply(M.askWaterMode())] };

    case STATE.WATER_START:
      if (event.kind === 'postback' && event.data === 'water:start' && picked !== null) {
        return { session: { state: STATE.WATER_END, draft: { start: picked } }, effects: [reply(M.askWaterTime('end', picked))] };
      }
      return { session: current, effects: [reply(M.askWaterTime('start'))] };

    case STATE.WATER_END:
      if (event.kind === 'postback' && event.data === 'water:end' && picked !== null) {
        if (picked === draft.start) {
          return { session: current, effects: [reply(M.text('เวลาสิ้นสุดต้องไม่ตรงกับเวลาเริ่ม'), M.askWaterTime('end', draft.start))] };
        }
        const next = { start: draft.start, end: picked };
        return { session: { state: STATE.WATER_MINUTES, draft: next }, effects: [reply(M.askWaterMinutes(next, WATER_MINUTE_CHOICES))] };
      }
      return { session: current, effects: [reply(M.askWaterTime('end', draft.start))] };

    default: {
      const minutes = minuteChoice(text);
      if (minutes === null) {
        return { session: current, effects: [reply(M.askWaterMinutes(draft.allDay ? null : draft, WATER_MINUTE_CHOICES))] };
      }
      const rule = draft.allDay ? { allDay: true, minutes } : { start: draft.start, end: draft.end, minutes };
      return { session: current, effects: [{ type: 'addWaterRule', rule }] };
    }
  }
}

export function handle(session, binding, event) {
  const current = session && session.state ? session : idle();

  if (event.kind === 'follow') {
    return { session: idle(), effects: [reply(M.welcome(isBound(binding)))] };
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
        effects: [reply(M.askDetail())],
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

    case STATE.WATER_RULE:
    case STATE.WATER_START:
    case STATE.WATER_END:
    case STATE.WATER_MINUTES:
      return handleWater(current, text, event);

    default:
      return { session: idle(), effects: [reply(M.help(isBound(binding)))] };
  }
}
