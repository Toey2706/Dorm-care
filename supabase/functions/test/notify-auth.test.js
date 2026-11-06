import test from 'node:test';
import assert from 'node:assert/strict';
import { notifyResident, NotifyError } from '../_shared/notify.js';
import { sendLoginOtp, requestPasswordReset, confirmPasswordReset, jwtClaims, AuthError } from '../_shared/auth.js';

const quiet = { warn: () => {}, error: () => {} };
const RID = '0b8a9f2e-6c1d-4f3a-9b7e-2d5c8e1f4a60';
const noPhotos = async () => [];

function notifyDb() {
  const log = {};
  const calls = [];
  const rpc = async (fn, a) => {
    calls.push(fn);
    if (fn === 'begin_notify') {
      if (log[a.p_request_id] === 'SENT') return { action: 'DUPLICATE' };
      log[a.p_request_id] = 'SENDING';
      return { action: 'SEND', ticket: { ticket_no: 'R2569-0001', room_no: '305', category: 'PLUMBING', repair_result: 'เปลี่ยนซีล', line_user_id: 'U1' } };
    }
    if (fn === 'finish_notify') {
      if (rpc.failFinish) throw new Error('db down');
      log[a.p_request_id] = a.p_ok ? 'SENT' : 'FAILED';
    }
  };
  return { rpc, log, calls };
}

function lineClient() {
  const sent = [];
  return { sent, push: async (to, msgs, key) => { if (lineClient.down) throw new Error('LINE 500'); sent.push({ to, key, text: msgs[0].text, msgs }); } };
}

test('แจ้งผลสำเร็จ แล้วเรียกซ้ำด้วยรหัสเดิมไม่ส่งซ้ำ', async () => {
  const db = notifyDb();
  const client = lineClient();
  assert.deepEqual(await notifyResident({ rpc: db.rpc, client, logger: quiet, photoUrls: noPhotos }, { ticketId: 'r_1', requestId: RID }), { ok: true });
  assert.equal(client.sent.length, 1);
  assert.equal(client.sent[0].key, RID);
  assert.match(client.sent[0].text, /ประปา[\s\S]*เปลี่ยนซีล/);
  assert.deepEqual(await notifyResident({ rpc: db.rpc, client, logger: quiet, photoUrls: noPhotos }, { ticketId: 'r_1', requestId: RID }), { ok: true, duplicate: true });
  assert.equal(client.sent.length, 1);
});

test('LINE ส่งแล้วแต่บันทึกไม่สำเร็จ ยังตอบว่าสำเร็จ', async () => {
  const db = notifyDb();
  db.rpc.failFinish = true;
  const r = await notifyResident({ rpc: db.rpc, client: lineClient(), logger: quiet, photoUrls: noPhotos }, { ticketId: 'r_1', requestId: RID });
  assert.deepEqual(r, { ok: true, logged: false });
});

test('LINE ล่ม แจ้งว่าล้มเหลวและบันทึก FAILED ลองใหม่ด้วยรหัสเดิมได้', async () => {
  const db = notifyDb();
  const client = lineClient();
  lineClient.down = true;
  await assert.rejects(notifyResident({ rpc: db.rpc, client, logger: quiet, photoUrls: noPhotos }, { ticketId: 'r_1', requestId: RID }), (e) => e instanceof NotifyError && e.status === 503);
  assert.equal(db.log[RID], 'FAILED');
  lineClient.down = false;
  await notifyResident({ rpc: db.rpc, client, logger: quiet, photoUrls: noPhotos }, { ticketId: 'r_1', requestId: RID });
  assert.equal(db.log[RID], 'SENT');
});

test('แจ้งผลพร้อมรูปหลังซ่อม ส่งข้อความกับรูปใน push เดียว ลิงก์อายุ 30 วัน', async () => {
  const db = notifyDb();
  const client = lineClient();
  let asked;
  const photoUrls = async (id, seconds) => { asked = { id, seconds }; return ['https://x.test/1.jpg', 'https://x.test/2.jpg', 'https://x.test/3.jpg', 'https://x.test/4.jpg']; };
  await notifyResident({ rpc: db.rpc, client, logger: quiet, photoUrls }, { ticketId: 'r_1', requestId: RID });
  assert.deepEqual(asked, { id: 'r_1', seconds: 30 * 86400 });
  const msgs = client.sent[0].msgs;
  assert.equal(msgs.length, 4);
  assert.match(msgs[0].text, /รูปหลังซ่อม 3 รูป[\s\S]*30 วัน/);
  assert.deepEqual(msgs[1], { type: 'image', originalContentUrl: 'https://x.test/1.jpg', previewImageUrl: 'https://x.test/1.jpg' });
});

test('สร้างลิงก์รูปไม่ได้ ยังส่งผลการซ่อมเป็นข้อความ', async () => {
  const db = notifyDb();
  const client = lineClient();
  const warns = [];
  const photoUrls = async () => { throw new Error('storage down'); };
  const r = await notifyResident({ rpc: db.rpc, client, logger: { ...quiet, warn: (m) => warns.push(m) }, photoUrls }, { ticketId: 'r_1', requestId: RID });
  assert.deepEqual(r, { ok: true });
  assert.equal(client.sent[0].msgs.length, 1);
  assert.doesNotMatch(client.sent[0].text, /รูปหลังซ่อม/);
  assert.equal(warns.length, 1);
  assert.equal(db.log[RID], 'SENT');
});

test('รหัสคำขอไม่ใช่ UUID ไม่เรียกฐานข้อมูล', async () => {
  const db = notifyDb();
  await assert.rejects(notifyResident({ rpc: db.rpc, client: lineClient(), logger: quiet, photoUrls: noPhotos }, { ticketId: 'r_1', requestId: 'abc' }), /รหัสคำขอ/);
  assert.equal(db.calls.length, 0);
});

test('OTP ล็อกอิน: ส่งอีเมลพร้อมรหัส และแจ้งเวลารอเมื่อขอถี่', async () => {
  const mails = [];
  let cooldown = false;
  const rpc = async (fn, a) => {
    assert.equal(a.p_session_id, 's1');
    return cooldown ? { ok: false, error: 'COOLDOWN', retry_in: 42 } : { ok: true, code: '482913', email: 'a@x.test', name: 'สมศรี', ttl_min: 10 };
  };
  const sendMail = async (to, m) => mails.push({ to, ...m });
  await sendLoginOtp({ rpc, sendMail }, { userId: 'u1', sessionId: 's1' });
  assert.equal(mails[0].to, 'a@x.test');
  assert.match(mails[0].text, /482913[\s\S]*10 นาที/);
  cooldown = true;
  await assert.rejects(sendLoginOtp({ rpc, sendMail }, { userId: 'u1', sessionId: 's1' }), (e) => e.status === 429 && e.extra.retry_in === 42);
  await assert.rejects(sendLoginOtp({ rpc, sendMail }, {}), (e) => e.status === 401);
});

test('ลืมรหัสผ่าน: อีเมลที่ไม่มีในระบบตอบเหมือนอีเมลที่มี', async () => {
  const mails = [];
  const rpc = async (fn, a) => (a.p_email === 'staff@x.test' ? { ok: true, code: '111111', email: a.p_email, name: 'ก', ttl_min: 10 } : { ok: false, error: 'NO_USER' });
  const deps = { rpc, sendMail: async (to) => mails.push(to), logger: quiet, photoUrls: noPhotos };
  assert.deepEqual(await requestPasswordReset(deps, { email: ' Staff@x.test ' }), { ok: true });
  assert.deepEqual(await requestPasswordReset(deps, { email: 'nobody@x.test' }), { ok: true });
  assert.deepEqual(mails, ['staff@x.test']);
  await assert.rejects(requestPasswordReset(deps, { email: 'not-an-email' }), (e) => e.status === 400);
});

test('ตั้งรหัสผ่านใหม่: รหัสผ่านสั้นไม่เปลืองรหัส OTP, รหัสถูกแล้วออกจากระบบทุกเครื่อง', async () => {
  const calls = [];
  const rpc = async (fn, a) => {
    calls.push(fn);
    if (fn === 'svc_verify_reset_otp') return a.p_code === '111111' ? { ok: true, user_id: 'u1' } : { ok: false, error: 'INVALID' };
  };
  const passwords = [];
  const deps = { rpc, setPassword: async (id, p) => passwords.push([id, p]) };
  await assert.rejects(confirmPasswordReset(deps, { email: 'a@x.test', code: '111111', newPassword: 'short' }), (e) => e.code === 'weak-password');
  assert.equal(calls.length, 0);
  await assert.rejects(confirmPasswordReset(deps, { email: 'a@x.test', code: '000000', newPassword: 'longenough' }), (e) => e instanceof AuthError && e.code === 'invalid');
  await confirmPasswordReset(deps, { email: 'a@x.test', code: '111111', newPassword: 'longenough' });
  assert.deepEqual(passwords, [['u1', 'longenough']]);
  assert.equal(calls.at(-1), 'svc_after_password_reset');
});

test('อ่าน sub และ session_id จาก JWT', () => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const token = `${b64({ alg: 'HS256' })}.${b64({ sub: 'u1', session_id: 's1', role: 'authenticated', name: 'ทดสอบ' })}.sig`;
  assert.deepEqual(jwtClaims(`Bearer ${token}`), { userId: 'u1', sessionId: 's1', role: 'authenticated' });
  assert.deepEqual(jwtClaims('garbage'), {});
});
