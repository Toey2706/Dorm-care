import test from 'node:test';
import assert from 'node:assert/strict';
import { handle, STATE } from '../_shared/conversation.js';

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
