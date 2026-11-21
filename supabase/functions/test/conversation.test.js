import test from 'node:test';
import assert from 'node:assert/strict';
import { handle, STATE, parseWaterRule, parseDuration } from '../_shared/conversation.js';

const active = { status: 'ACTIVE', roomNo: '305' };
const say = (text) => ({ kind: 'text', text });
const types = (r) => r.effects.map((e) => e.type);

test('แจ้งซ่อมครบขั้นตอน พร้อมรูป 1 รูป', () => {
  let r = handle(null, active, say('แจ้งซ่อม'));
  assert.equal(r.session.state, STATE.REPORT_CATEGORY);
  r = handle(r.session, active, say('ประปา'));
  assert.equal(r.session.draft.category, 'PLUMBING');
  r = handle(r.session, active, say('ก๊อกอ่างล้างหน้ารั่ว'));
  assert.equal(r.session.state, STATE.REPORT_PHOTO);
  r = handle(r.session, active, { kind: 'image', messageId: 'm1' });
  assert.deepEqual(r.session.draft.photoMessageIds, ['m1']);
  r = handle(r.session, active, say('เสร็จ'));
  assert.equal(r.session.state, STATE.REPORT_CONFIRM);
  r = handle(r.session, active, say('ยืนยัน'));
  assert.deepEqual(types(r), ['createTicket']);
  assert.equal(r.effects[0].draft.description, 'ก๊อกอ่างล้างหน้ารั่ว');
  assert.equal(r.session.state, STATE.REPORT_CONFIRM, 'คงร่างไว้จนกว่า Backend สร้างใบงานสำเร็จ');
});

test('ยังไม่ผูกห้อง: แจ้งซ่อมจะพาไปใส่รหัสผูกห้องก่อน', () => {
  let r = handle(null, null, say('แจ้งซ่อม'));
  assert.equal(r.session.state, STATE.BIND_WAIT_CODE);
  r = handle(r.session, null, say('123 456'));
  assert.deepEqual(r.effects, [{ type: 'redeemCode', code: '123456' }]);
});

test('ผูกห้องถูกยกเลิกแล้ว (ย้ายออก): แจ้งซ่อมไม่ได้ ต้องใส่รหัสใหม่', () => {
  const r = handle(null, { status: 'REVOKED', roomNo: '305' }, say('แจ้งซ่อม'));
  assert.equal(r.session.state, STATE.BIND_WAIT_CODE);
});

test('รหัสผิดรูปแบบ ถามซ้ำ', () => {
  for (const bad of ['12345', 'abcdef', '1234567']) {
    const r = handle({ state: STATE.BIND_WAIT_CODE, draft: null }, null, say(bad));
    assert.equal(r.session.state, STATE.BIND_WAIT_CODE);
    assert.deepEqual(types(r), ['reply']);
  }
});

test('ยกเลิกได้ทุกขั้น และปุ่มเมนูขัดจังหวะได้', () => {
  const mid = { state: STATE.REPORT_DETAIL, draft: { category: 'PLUMBING', photoMessageIds: [] } };
  assert.equal(handle(mid, active, say('ยกเลิก')).session.state, STATE.IDLE);
  assert.deepEqual(types(handle(mid, active, say('ติดตามงาน'))), ['showStatus']);
});

test('รูปครบ 3 รูปไปขั้นยืนยันอัตโนมัติ', () => {
  let s = { state: STATE.REPORT_PHOTO, draft: { category: 'OTHER', description: 'x', photoMessageIds: [] } };
  for (const id of ['a', 'b', 'c']) s = handle(s, active, { kind: 'image', messageId: id }).session;
  assert.equal(s.state, STATE.REPORT_CONFIRM);
  assert.equal(s.draft.photoMessageIds.length, 3);
});

test('ผูกห้องแล้วกดผูกซ้ำ แจ้งว่าผูกแล้ว', () => {
  const r = handle(null, active, say('ผูกเลขห้อง'));
  assert.match(r.effects[0].messages[0].altText ?? r.effects[0].messages[0].text, /ผูกกับห้อง 305 แล้ว/);
});

test('อ่านช่วงเวลาแจ้งเตือนน้ำได้หลายรูปแบบ และปฏิเสธค่าที่ไม่ถูกต้อง', () => {
  assert.deepEqual(parseWaterRule('09:00-10:00 30'), { start: 540, end: 600, minutes: 30 });
  assert.deepEqual(parseWaterRule('9.00 - 10.00 30 นาที'), { start: 540, end: 600, minutes: 30 });
  assert.deepEqual(parseWaterRule('22:00 ถึง 02:00 60'), { start: 1320, end: 120, minutes: 60 });
  assert.deepEqual(parseWaterRule('23:00-24:00 15'), { start: 1380, end: 0, minutes: 15 });
  assert.deepEqual(parseWaterRule('09:00-10:00 7'), { start: 540, end: 600, minutes: 7 });
  assert.equal(parseWaterRule('09:00-10:00 0'), null);
  assert.equal(parseWaterRule('09:00-10:00 181'), null);
  assert.equal(parseWaterRule('09:00-09:00 30'), null);
  assert.equal(parseWaterRule('25:00-10:00 30'), null);
  assert.equal(parseWaterRule('9 โมง 30 นาที'), null);
  assert.deepEqual(parseWaterRule('ทั้งวัน 20'), { allDay: true, minutes: 20 });
  assert.deepEqual(parseWaterRule('ทั้งวัน 15 นาที'), { allDay: true, minutes: 15 });
  assert.deepEqual(parseWaterRule('ทั้งวัน 3'), { allDay: true, minutes: 3 });
  assert.equal(parseWaterRule('ทั้งวัน 200'), null);
});

test('ตั้งแจ้งเตือนน้ำ: ต้องผูกห้องก่อน และพิมพ์ผิดยังอยู่ขั้นเดิม', () => {
  assert.match(handle(null, null, say('ตั้งแจ้งเตือนน้ำ')).effects[0].messages[0].text, /ผูกเลขห้อง/);
  let r = handle(null, active, say('ตั้งแจ้งเตือนน้ำ'));
  assert.deepEqual(types(r), ['showWaterRules']);
  r = handle(r.session, active, say('ตั้งเวลาแจ้งเตือน'));
  assert.equal(r.session.state, STATE.WATER_RULE);
  r = handle(r.session, active, say('เก้าโมง'));
  assert.equal(r.session.state, STATE.WATER_RULE);
  r = handle(r.session, active, say('09:00-10:00 30'));
  assert.deepEqual(r.effects, [{ type: 'addWaterRule', rule: { start: 540, end: 600, minutes: 30 } }]);
  r = handle(r.session, active, say('ยกเลิก'));
  assert.equal(r.session.state, STATE.IDLE);
});

test('ตั้งเวลาแจ้งเตือนแบบกดปุ่ม: เลือกเวลาเริ่ม เวลาสิ้นสุด แล้วเลือกนาที', () => {
  const pick = (data, time) => ({ kind: 'postback', data, params: { time } });
  let r = handle(null, active, say('ตั้งเวลาแจ้งเตือน'));
  assert.equal(r.session.state, STATE.WATER_RULE);
  r = handle(r.session, active, say('เฉพาะช่วงเวลา'));
  assert.equal(r.session.state, STATE.WATER_START);
  r = handle(r.session, active, pick('water:end', '10:00'));
  assert.equal(r.session.state, STATE.WATER_START, 'กดปุ่มเก่าผิดขั้นไม่ไปต่อ');
  r = handle(r.session, active, pick('water:start', '09:00'));
  assert.deepEqual(r.session, { state: STATE.WATER_END, draft: { start: 540 } });
  r = handle(r.session, active, pick('water:end', '09:00'));
  assert.equal(r.session.state, STATE.WATER_END, 'เวลาเดียวกันไม่ได้');
  r = handle(r.session, active, pick('water:end', '10:00'));
  assert.deepEqual(r.session, { state: STATE.WATER_MINUTES, draft: { start: 540, end: 600 } });
  r = handle(r.session, active, say('เยอะๆ'));
  assert.equal(r.session.state, STATE.WATER_MINUTES);
  r = handle(r.session, active, say('30 นาที'));
  assert.deepEqual(r.effects, [{ type: 'addWaterRule', rule: { start: 540, end: 600, minutes: 30 } }]);
});

test('ตั้งเวลาแจ้งเตือนแบบกดปุ่ม: ทั้งวัน', () => {
  let r = handle(null, active, say('ตั้งเวลาแจ้งเตือน'));
  r = handle(r.session, active, say('ทั้งวัน'));
  assert.deepEqual(r.session, { state: STATE.WATER_MINUTES, draft: { allDay: true } });
  r = handle(r.session, active, say('20'));
  assert.deepEqual(r.effects, [{ type: 'addWaterRule', rule: { allDay: true, minutes: 20 } }]);
});

test('ตั้งเวลาแจ้งเตือนน้ำได้ถึงระดับ 30 วินาที', () => {
  assert.equal(parseDuration('30 วินาที'), 0.5);
  assert.equal(parseDuration('90 วินาที'), 1.5);
  assert.equal(parseDuration('1.5'), 1.5);
  assert.equal(parseDuration('2 นาที 30 วินาที'), 2.5);
  assert.equal(parseDuration('7 นาที'), 7);
  assert.equal(parseDuration('20 วินาที'), null);
  assert.equal(parseDuration('1.2'), null);
  assert.equal(parseDuration('181'), null);
  assert.deepEqual(parseWaterRule('ทั้งวัน 30 วินาที'), { allDay: true, minutes: 0.5 });
  assert.deepEqual(parseWaterRule('09:00-10:00 1 นาที 30 วินาที'), { start: 540, end: 600, minutes: 1.5 });
});
