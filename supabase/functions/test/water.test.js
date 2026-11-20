import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleWaterAlert, keyMatches, summarizeTelemetry, waterStatus } from '../_shared/water.js';
import { thingsboard } from '../_shared/thingsboard.js';

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

test('บันทึกแจ้งเตือนพร้อมจำนวนผู้พักที่ได้รับการ์ด', async () => {
  const rows = [];
  const { d } = deps({ record: async (r) => rows.push(r) });
  await handleWaterAlert(d, { room: 'A1-01', minutes: 11, flow_lpm: 2, total_l: 30 });
  assert.deepEqual(rows, [{ room_no: 'A1-01', minutes: 11, flow_lpm: 2, total_l: 30, line_sent: 2 }]);
});

test('บันทึกไม่สำเร็จก็ยังส่งแจ้งเตือนครบ', async () => {
  const { d, pushed } = deps({ record: async () => { throw new Error('db down'); } });
  const r = await handleWaterAlert(d, { room: 'A1-01', minutes: 11 });
  assert.equal(r.line, 2);
  assert.equal(pushed.length, 2);
});

const series = (ts, over = {}) => {
  const v = { flow_lpm: '3.5', total_l: '120.4', flowing: 'true', flow_seconds: '90', leak: 'false', rssi: '-55', ...over };
  return Object.fromEntries(Object.entries(v).map(([k, value]) => [k, [{ ts, value }]]));
};

test('สรุปค่าล่าสุดและสถานะจาก telemetry', () => {
  const now = Date.parse('2026-11-19T16:00:00Z');
  const s = summarizeTelemetry(series(now - 5000), now);
  assert.equal(s.online, true);
  assert.equal(s.flow_lpm, 3.5);
  assert.equal(s.total_l, 120.4);
  assert.equal(s.state, 'FLOWING');
  assert.equal(summarizeTelemetry(series(now, { leak: 'true' }), now).state, 'LEAK');
  assert.equal(summarizeTelemetry(series(now, { flowing: 'false' }), now).state, 'IDLE');
});

test('ไม่ส่งข้อมูลเกิน 1 นาทีถือว่าออฟไลน์ และไม่มีข้อมูลเลยก็ออฟไลน์', () => {
  const now = Date.parse('2026-11-19T16:00:00Z');
  assert.equal(summarizeTelemetry(series(now - 61_000), now).online, false);
  assert.deepEqual(summarizeTelemetry({}, now), { online: false, last_seen: null });
});

test('อุปกรณ์ที่อ่านค่าไม่ได้ไม่ทำให้รายการทั้งหมดล้ม', async () => {
  const list = await waterStatus({
    devices: async () => [{ id: 'WF-001', room_no: 'A1-01', tb_device_id: 'a' }, { id: 'WF-002', room_no: 'B2-03', tb_device_id: 'b' }],
    telemetry: async (id) => { if (id === 'b') throw new Error('502'); return series(Date.now()); },
    logger: { error() {} },
  });
  assert.equal(list[0].online, true);
  assert.equal(list[1].online, false);
  assert.ok(list[1].error);
});

test('ThingsBoard ล็อกอินแบบ public ครั้งเดียวแล้วใช้โทเคนซ้ำ และล็อกอินใหม่เมื่อโทเคนหมดอายุ', async () => {
  const calls = [];
  let expired = false;
  const fetch = async (url, opt = {}) => {
    calls.push(url);
    if (url.endsWith('/login/public')) {
      assert.deepEqual(JSON.parse(opt.body), { publicId: 'P' });
      return { ok: true, json: async () => ({ token: `T${calls.length}` }) };
    }
    if (expired) { expired = false; return { ok: false, status: 401 }; }
    return { ok: true, status: 200, json: async () => ({ flow_lpm: [] }) };
  };
  const tb = thingsboard({ publicId: 'P', fetch });
  await tb.telemetry('d1', ['flow_lpm']);
  await tb.telemetry('d1', ['flow_lpm']);
  assert.equal(calls.filter((u) => u.endsWith('/login/public')).length, 1);
  expired = true;
  await tb.telemetry('d1', ['flow_lpm']);
  assert.equal(calls.filter((u) => u.endsWith('/login/public')).length, 2);
});

test('ไม่ส่งแจ้งเตือนผู้ดูแลเมื่อไม่ได้ตั้ง staff ส่งเฉพาะผู้พัก', async () => {
  const errors = [];
  const { d, pushed } = deps({ staff: undefined, logger: { error: (m) => errors.push(m), warn() {} } });
  const r = await handleWaterAlert(d, { room: 'A1-01', minutes: 10 });
  assert.equal(r.line, 2);
  assert.equal(pushed.length, 2);
  assert.deepEqual(r.staff, { sent: 0 });
  assert.deepEqual(errors, []);
});

test('เตือนเมื่อเวลาไหลข้ามค่าที่ตั้งไว้ครั้งเดียว ใช้เวลาเริ่มไหลหาช่วงเวลา', async () => {
  const asked = [];
  const threshold = async (room, startedAt) => (asked.push(startedAt.toISOString()), 30);
  for (const [minutes, expectSent] of [[10, false], [25, false], [30, true], [35, false], [60, false]]) {
    const { d, pushed } = deps({ threshold });
    const r = await handleWaterAlert(d, { room: 'A1-01', minutes });
    assert.equal(pushed.length > 0, expectSent, `minutes ${minutes}`);
    assert.equal(r.threshold, 30);
    if (!expectSent) assert.equal(r.skipped, true);
  }
  assert.equal(asked[2], '2026-11-19T14:30:00.000Z');
});

test('ค่าที่ตั้งไม่หาร 5 ลงตัวก็ยังเตือนที่รอบแรกที่เกิน', async () => {
  const { d, pushed } = deps({ threshold: async () => 12 });
  await handleWaterAlert(d, { room: 'A1-01', minutes: 15 });
  assert.equal(pushed.length, 2);
});

test('คำสั่งทดสอบส่งทันทีโดยไม่ดูช่วงเวลา และการ์ดบอกว่าเป็นการทดสอบ', async () => {
  const { d, pushed } = deps({ threshold: async () => 30 });
  await handleWaterAlert(d, { room: 'A1-01', minutes: 0, test: true });
  assert.equal(pushed.length, 2);
  assert.match(pushed[0][1][0].altText, /ทดสอบการแจ้งเตือน/);
});
