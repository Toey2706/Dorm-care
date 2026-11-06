import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { verifySignature, sha256Hex, createClient } from '../_shared/line.js';
import { buddhistYear, ticketNumber, thaiDateTime, statusLabel } from '../_shared/format.js';

test('ตรวจลายเซ็น LINE', async () => {
  const body = new TextEncoder().encode('{"events":[]}');
  const sig = createHmac('sha256', 'secret').update(body).digest('base64');
  assert.equal(await verifySignature(body, sig, 'secret'), true);
  assert.equal(await verifySignature(body, sig, 'wrong'), false);
  assert.equal(await verifySignature(body, sig.slice(0, -2) + 'AA', 'secret'), false);
  assert.equal(await verifySignature(body, undefined, 'secret'), false);
});

test('sha256 ตรงกับฝั่งฐานข้อมูล', async () => {
  // ค่าเดียวกับ select encode(digest('123456','sha256'),'hex')
  assert.equal(await sha256Hex('123456'), '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92');
});

test('เลขที่ใบแจ้งซ่อม ปี พ.ศ. และสถานะ', () => {
  assert.equal(ticketNumber(2569, 41), 'R2569-0041');
  assert.equal(buddhistYear(new Date('2026-12-31T18:00:00Z')), 2570); // 01:00 ของ 1 ม.ค. ตามเวลาไทย
  assert.match(thaiDateTime(new Date('2026-10-26T01:40:00Z')), /^26 ต\.ค\. 2569 08:40$/);
  assert.equal(statusLabel('PENDING', true), 'รอดำเนินการ (มอบหมายแล้ว)');
  assert.equal(statusLabel('COMPLETED', false), 'ซ่อมเสร็จแล้ว');
});

test('push ที่ LINE ตอบ 409 ด้วย retry key เดิม ถือว่าส่งแล้ว', async () => {
  const calls = [];
  const fake = async (url, init) => {
    calls.push(init.headers['X-Line-Retry-Key']);
    return { ok: false, status: 409, text: async () => 'conflict' };
  };
  const client = createClient('token', fake);
  assert.deepEqual(await client.push('U1', [{ type: 'text', text: 'x' }], 'k1'), { alreadySent: true });
  assert.deepEqual(calls, ['k1']);
  await assert.rejects(client.push('U1', [{ type: 'text', text: 'x' }]), /409/);
});
