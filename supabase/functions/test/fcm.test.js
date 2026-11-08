import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { createFcm, notifyStaff, signedAssertion, staffMessage } from '../_shared/fcm.js';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const account = {
  client_email: 'svc@dorm-care.iam.gserviceaccount.com',
  private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  token_uri: 'https://oauth2.googleapis.com/token',
  project_id: 'dorm-care',
};

test('JWT ที่เซ็นตรวจได้ด้วยกุญแจสาธารณะ และมี scope ของ FCM', async () => {
  const jwt = await signedAssertion(account, 1000);
  const [h, c, s] = jwt.split('.');
  const v = createVerify('RSA-SHA256');
  v.update(`${h}.${c}`);
  assert.ok(v.verify(publicKey, Buffer.from(s, 'base64url')));
  const claims = JSON.parse(Buffer.from(c, 'base64url').toString());
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  assert.equal(claims.exp - claims.iat, 3600);
});

function fakeFetch(responses) {
  const calls = [];
  const impl = async (url, init) => {
    calls.push({ url, init });
    if (url === account.token_uri) return new Response(JSON.stringify({ access_token: 'AT', expires_in: 3600 }));
    const token = JSON.parse(init.body).message.token;
    const [status, text] = responses[token] || [200, '{}'];
    return new Response(text, { status });
  };
  return { impl, calls };
}

test('ขอ access token ครั้งเดียวแล้วใช้ซ้ำ และแยกเครื่องที่ใช้ไม่ได้แล้ว', async () => {
  const f = fakeFetch({ dead: [404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'] });
  const fcm = createFcm(account, { fetchImpl: f.impl, now: () => 1_000_000 });
  assert.equal(await fcm.send('live', { title: 't', body: 'b', data: { n: 1 } }), 'sent');
  assert.equal(await fcm.send('dead', { title: 't', body: 'b' }), 'invalid');
  assert.equal(f.calls.filter((c) => c.url === account.token_uri).length, 1);
  const sent = JSON.parse(f.calls[1].init.body).message;
  assert.equal(sent.data.n, '1');
  assert.equal(f.calls[1].init.headers.Authorization, 'Bearer AT');
});

test('ส่งถึงหลายเครื่อง ลบรหัสที่ตายแล้ว เครื่องที่พลาดไม่ทำให้เครื่องอื่นพลาด', async () => {
  const f = fakeFetch({ dead: [404, 'UNREGISTERED'], flaky: [500, 'oops'] });
  const removed = [];
  const r = await notifyStaff(
    {
      fcm: createFcm(account, { fetchImpl: f.impl }),
      devices: async () => ['a', 'dead', 'flaky', 'b'],
      removeDevices: async (t) => removed.push(...t),
      logger: { warn: () => {} },
    },
    ['u1'],
    { title: 't', body: 'b' }
  );
  assert.deepEqual(r, { sent: 2, removed: 1, failed: 1 });
  assert.deepEqual(removed, ['dead']);
});

test('ยังไม่ได้ตั้ง Firebase ไม่ส่งอะไรและไม่ error', async () => {
  const r = await notifyStaff({ fcm: null, devices: async () => assert.fail(), removeDevices: async () => {}, logger: {} }, ['u1'], {});
  assert.equal(r.sent, 0);
});

test('ข้อความแจ้งเตือนมีห้อง หมวด เลขที่ และ ticket_id', () => {
  const m = staffMessage('assigned', { id: 'r_1', ticket_no: 'R2569-0013', room_no: 'A1-02', category: 'AIRCON' });
  assert.match(m.body, /ห้อง A1-02 · เครื่องปรับอากาศ · R2569-0013/);
  assert.equal(m.data.ticket_id, 'r_1');
});
