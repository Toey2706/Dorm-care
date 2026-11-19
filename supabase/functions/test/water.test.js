import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleWaterAlert, keyMatches } from '../_shared/water.js';

const deps = (over = {}) => {
  const pushed = [];
  const staffMsgs = [];
  return {
    pushed,
    staffMsgs,
    d: {
      roomExists: async (r) => r === 'A1-01',
      residents: async () => ['U1', 'U2'],
      push: async (to, m) => pushed.push([to, m]),
      staff: async (m) => (staffMsgs.push(m), { sent: 1 }),
      logger: { error() {}, warn() {} },
      now: () => new Date('2026-11-19T15:00:00Z'),
      ...over,
    },
  };
};

test('ส่งการ์ดแจ้งเตือนถึงผู้พักทุกคนที่ผูกห้องและแจ้งผู้ดูแล', async () => {
  const { d, pushed, staffMsgs } = deps();
  const r = await handleWaterAlert(d, { room: 'a1-01', minutes: 12, flow_lpm: 3.456, total_l: 40.21 });
  assert.equal(r.line, 2);
  assert.equal(pushed[0][1][0].type, 'flex');
  assert.match(pushed[0][1][0].altText, /A1-01[\s\S]*12 นาที[\s\S]*3.46/);
  assert.equal(staffMsgs[0].data.room, 'A1-01');
});

test('ห้องที่ไม่มีในระบบถูกปฏิเสธ และไม่ส่งอะไรออกไป', async () => {
  const { d, pushed } = deps();
  await assert.rejects(handleWaterAlert(d, { room: 'Z9-99', minutes: 1 }), (e) => e.status === 404);
  assert.equal(pushed.length, 0);
});

test('ค่าตัวเลขติดลบถูกปฏิเสธ', async () => {
  const { d } = deps();
  await assert.rejects(handleWaterAlert(d, { room: 'A1-01', minutes: -1 }), (e) => e.status === 400);
});

test('ส่ง LINE ไม่ผ่านบางคนยังส่งคนที่เหลือและแจ้งผู้ดูแลต่อ', async () => {
  const { d, staffMsgs } = deps({ push: async (to) => { if (to === 'U1') throw Object.assign(new Error('x'), { status: 400 }); } });
  const r = await handleWaterAlert(d, { room: 'A1-01', minutes: 5 });
  assert.equal(r.line, 1);
  assert.equal(staffMsgs.length, 1);
});

test('ตรวจคีย์อุปกรณ์', async () => {
  assert.equal(await keyMatches('abc', 'abc'), true);
  assert.equal(await keyMatches('abd', 'abc'), false);
  assert.equal(await keyMatches('', 'abc'), false);
  assert.equal(await keyMatches('abc', ''), false);
});
