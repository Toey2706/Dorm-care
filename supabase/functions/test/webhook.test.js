import test from 'node:test';
import assert from 'node:assert/strict';
import { createWebhook } from '../_shared/webhook.js';

// ฐานข้อมูลจำลองที่ทำตัวเหมือนฟังก์ชัน line_* ใน migration (ตัวจริงทดสอบแยกใน supabase/tests)
function fakeDb() {
  const s = { sessions: {}, bindings: {}, codes: { '123456': { room: '305', used: false } }, failed: {}, tickets: {}, processed: new Set(), seq: 0 };
  const fail = { createTicket: 0, crashOn: null };
  const fns = {
    line_context: ({ p_user_id }) => ({ session: s.sessions[p_user_id] || null, binding: s.bindings[p_user_id] || null }),
    line_save_session: ({ p_user_id, p_version, p_state, p_draft }) => {
      const cur = s.sessions[p_user_id];
      if ((cur ? cur.version : null) !== p_version) return false;
      s.sessions[p_user_id] = { state: p_state, draft: p_draft, version: (p_version || 0) + 1 };
      return true;
    },
    line_set_idle: ({ p_user_id }) => {
      const v = s.sessions[p_user_id] ? s.sessions[p_user_id].version : 0;
      s.sessions[p_user_id] = { state: 'IDLE', draft: null, version: v + 1 };
    },
    line_is_processed: ({ p_event_id }) => s.processed.has(p_event_id),
    line_mark_processed: ({ p_event_id }) => s.processed.add(p_event_id),
    line_redeem_code: ({ p_user_id, p_code, p_display_name }) => {
      if ((s.failed[p_user_id] || 0) >= 5) return { result: 'LIMIT' };
      const c = s.codes[p_code];
      if (!c || c.used) {
        s.failed[p_user_id] = (s.failed[p_user_id] || 0) + 1;
        return { result: 'INVALID' };
      }
      c.used = true;
      s.bindings[p_user_id] = { status: 'ACTIVE', room_no: c.room, display_name: p_display_name };
      return { result: 'BOUND', room_no: c.room };
    },
    line_ticket_no: ({ p_ticket_id }) => (s.tickets[p_ticket_id] || {}).ticket_no || null,
    line_create_ticket: (a) => {
      if (s.tickets[a.p_ticket_id]) return { ticket_no: s.tickets[a.p_ticket_id].ticket_no, room_no: '305' };
      if (fail.createTicket > 0) {
        fail.createTicket -= 1;
        throw new Error('db down');
      }
      const b = s.bindings[a.p_user_id];
      if (!b || b.status !== 'ACTIVE') return { error: 'NOT_BOUND' };
      s.seq += 1;
      s.tickets[a.p_ticket_id] = { ticket_no: `R2569-${String(s.seq).padStart(4, '0')}`, photos: a.p_photo_paths };
      return { ticket_no: s.tickets[a.p_ticket_id].ticket_no, room_no: b.room_no };
    },
    line_recent_tickets: () => [],
    line_contact_text: () => null,
  };
  const rpc = async (fn, args = {}) => {
    if (fail.crashOn === fn) throw new Error('unexpected');
    return fns[fn](args);
  };
  return { s, fail, rpc };
}

function fakeLine() {
  const replies = [];
  const failContent = new Set();
  return {
    replies,
    failContent,
    client: {
      reply: async (token, messages) => replies.push(...messages.map((m) => m.text ?? m.altText)),
      getProfile: async () => ({ displayName: 'สมชาย' }),
      getContent: async (id) => {
        if (failContent.has(id)) throw new Error('LINE content 500');
        return { bytes: new Uint8Array([1, 2, 3]), contentType: 'image/jpeg' };
      },
    },
  };
}

function setup() {
  const db = fakeDb();
  const line = fakeLine();
  const saved = [];
  const errors = [];
  const menu = [];
  const hook = createWebhook({
    rpc: db.rpc,
    storage: { save: async (path) => saved.push(path) },
    logger: { warn: () => {}, error: (m) => errors.push(m) },
    richMenu: {
      toBound: async (u) => { if (menu.fail) throw new Error('LINE 500'); menu.push(['bound', u]); },
      toDefault: async (u) => menu.push(['default', u]),
    },
  });
  let n = 0;
  const send = async (message, at = 1000) => {
    n += 1;
    const ev = { type: 'message', webhookEventId: `e${n}`, replyToken: `t${n}`, timestamp: at, source: { type: 'user', userId: 'U1' }, message };
    return { ok: await hook.handleAll(line.client, [ev]), ev };
  };
  const say = (text, at) => send({ type: 'text', text }, at);
  const last = () => line.replies[line.replies.length - 1];
  const follow = () => hook.handleAll(line.client, [{ type: 'follow', webhookEventId: `f${++n}`, replyToken: `t${n}`, timestamp: 1000, source: { type: 'user', userId: 'U1' } }]);
  return { db, line, saved, errors, hook, send, say, last, menu, follow };
}

async function reportUntilConfirm(t, photos = []) {
  await t.say('แจ้งซ่อม', 5000);
  await t.say('ประปา');
  await t.say('ก๊อกอ่างล้างหน้ารั่ว');
  for (const id of photos) await t.send({ type: 'image', id });
  await t.say(photos.length ? 'เสร็จ' : 'ข้าม');
}

test('ผูกห้องด้วยรหัส แล้วแจ้งซ่อมได้ใบงาน 1 ใบ พร้อมรูป', async () => {
  const t = setup();
  await t.say('ผูกเลขห้อง');
  await t.say('123 456');
  assert.match(t.last(), /ห้อง 305 เรียบร้อย/);
  await reportUntilConfirm(t, ['m1', 'm2']);
  await t.say('ยืนยัน');
  assert.match(t.last(), /เลขที่: R2569-0001/);
  const [ticket] = Object.entries(t.db.s.tickets);
  assert.match(ticket[0], /^r_[0-9a-f]{24}$/);
  assert.deepEqual(ticket[1].photos, [`${ticket[0]}/1.jpg`, `${ticket[0]}/2.jpg`]);
  assert.equal(t.db.s.sessions.U1.state, 'IDLE');
});

test('สร้างใบงานล้มเหลว ข้อมูลยังอยู่ กดยืนยันใหม่แล้วได้ใบงาน (ไม่ซ้ำ)', async () => {
  const t = setup();
  t.db.s.bindings.U1 = { status: 'ACTIVE', room_no: '305', display_name: '' };
  await reportUntilConfirm(t);
  t.db.fail.createTicket = 1;
  await t.say('ยืนยัน');
  assert.match(t.last(), /ไม่สำเร็จ ข้อมูลที่กรอกยังอยู่/);
  assert.equal(t.db.s.sessions.U1.state, 'REPORT_CONFIRM');
  await t.say('ยืนยัน');
  await t.say('ยืนยัน'); // กดซ้ำหลังสำเร็จ ไม่มีร่างแล้ว ไม่เกิดใบใหม่
  assert.equal(Object.keys(t.db.s.tickets).length, 1);
});

test('ดึงรูปไม่สำเร็จ ไม่สร้างใบงาน ข้อมูลยังอยู่ให้ลองใหม่', async () => {
  const t = setup();
  t.db.s.bindings.U1 = { status: 'ACTIVE', room_no: '305', display_name: '' };
  await reportUntilConfirm(t, ['m1']);
  t.line.failContent.add('m1');
  await t.say('ยืนยัน');
  assert.equal(Object.keys(t.db.s.tickets).length, 0);
  assert.match(t.last(), /ไม่สำเร็จ/);
  t.line.failContent.clear();
  await t.say('ยืนยัน');
  assert.equal(Object.keys(t.db.s.tickets).length, 1);
});

test('ข้อผิดพลาดที่ไม่คาดคิดไม่ถูกบันทึกว่าทำเสร็จ และ webhook รายงานล้มเหลว', async () => {
  const t = setup();
  t.db.fail.crashOn = 'line_save_session';
  const { ok, ev } = await t.say('แจ้งซ่อม');
  assert.equal(ok, false);
  assert.equal(t.db.s.processed.has(ev.webhookEventId), false);
});

test('เหตุการณ์ที่ทำเสร็จแล้วถูกข้ามเมื่อ LINE ส่งซ้ำ', async () => {
  const t = setup();
  const { ev } = await t.say('ติดต่อผู้ดูแล');
  const before = t.line.replies.length;
  await t.hook.handleAll(t.line.client, [ev]);
  assert.equal(t.line.replies.length, before);
});

test('บันทึกสถานะชนกับเหตุการณ์อื่น อ่านใหม่แล้วไปต่อได้', async () => {
  const t = setup();
  t.db.s.bindings.U1 = { status: 'ACTIVE', room_no: '305', display_name: '' };
  const real = t.db.rpc;
  let bumped = false;
  const hook = createWebhook({
    rpc: async (fn, args) => {
      // จำลองว่ามีเหตุการณ์อื่นบันทึกแทรกเข้ามาก่อนครั้งแรก
      if (fn === 'line_save_session' && !bumped) {
        bumped = true;
        await real('line_set_idle', { p_user_id: 'U1' });
      }
      return real(fn, args);
    },
    storage: { save: async () => {} },
    logger: { warn: () => {}, error: () => {} },
  });
  const ev = { type: 'message', webhookEventId: 'x', replyToken: 'r', timestamp: 1, source: { type: 'user', userId: 'U1' }, message: { type: 'text', text: 'แจ้งซ่อม' } };
  assert.equal(await hook.handleAll(t.line.client, [ev]), true);
  assert.equal(t.db.s.sessions.U1.state, 'REPORT_CATEGORY');
});

test('รหัสผิดพิมพ์ใหม่ได้ทันที และผิดเกิน 5 ครั้งถูกล็อก', async () => {
  const t = setup();
  await t.say('ผูกเลขห้อง');
  await t.say('999999');
  assert.match(t.last(), /ไม่ถูกต้อง/);
  assert.equal(t.db.s.sessions.U1.state, 'BIND_WAIT_CODE');
  for (let i = 0; i < 4; i += 1) await t.say('999999');
  await t.say('123456');
  assert.match(t.last(), /ผิดหลายครั้งเกินไป/);
  assert.equal(t.db.s.sessions.U1.state, 'IDLE');
  assert.equal(t.db.s.bindings.U1, undefined);
});

test('เมนูด้านล่าง: แอดใหม่ได้เมนูเริ่มต้น ผูกห้องแล้วได้เมนูชุดผูกห้อง', async () => {
  const t = setup();
  await t.follow();
  assert.deepEqual(t.menu, [['default', 'U1']]);
  await t.say('ผูกเลขห้อง');
  await t.say('123456');
  assert.deepEqual(t.menu.at(-1), ['bound', 'U1']);
});

test('เมนูด้านล่าง: ถูกยกเลิกการผูกแล้วกดแจ้งซ่อม กลับเป็นเมนูเริ่มต้น', async () => {
  const t = setup();
  t.db.s.bindings.U1 = { status: 'REVOKED', room_no: '305', display_name: '' };
  await t.say('แจ้งซ่อม');
  assert.deepEqual(t.menu, [['default', 'U1']]);
});

test('เปลี่ยนเมนูไม่สำเร็จ ผู้ใช้ยังได้คำตอบว่าผูกห้องแล้ว', async () => {
  const t = setup();
  t.menu.fail = true;
  await t.say('ผูกเลขห้อง');
  const r = await t.say('123456');
  assert.equal(r.ok, true);
  assert.match(t.last(), /ห้อง 305 เรียบร้อย/);
});
