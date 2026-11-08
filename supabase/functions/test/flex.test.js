import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as M from '../_shared/messages.js';

// LINE ปฏิเสธทั้งคำขอถ้ามีข้อความว่างใน Flex จึงไล่ตรวจทุกโหนด
function texts(node, out = []) {
  if (Array.isArray(node)) node.forEach((n) => texts(n, out));
  else if (node && typeof node === 'object') {
    if (node.type === 'text') out.push(node.text);
    Object.values(node).forEach((v) => texts(v, out));
  }
  return out;
}

test('ใบรับแจ้งซ่อมเป็น Flex มี altText เดิมและปุ่มติดตามงาน', () => {
  const m = M.ticketCreated('R2569-0011', 'A1-01', { categoryLabel: 'ประปา', description: 'ก๊อกรั่ว', createdAtText: '8 พ.ย. 2569 15:00' });
  assert.equal(m.type, 'flex');
  assert.match(m.altText, /R2569-0011[\s\S]*A1-01/);
  assert.ok(texts(m.contents).includes('ก๊อกรั่ว'));
  assert.equal(m.contents.footer.contents[0].action.text, 'ติดตามงาน');
  assert.ok(texts(m.contents).every((t) => typeof t === 'string' && t.length > 0));
});

test('หน้ายืนยันมีปุ่มในการ์ดและ quick reply ทั้งคู่', () => {
  const m = M.confirmReport({ category: 'PLUMBING', description: 'x', photoMessageIds: ['a'] }, [{ code: 'PLUMBING', label: 'ประปา' }]);
  assert.deepEqual(m.contents.footer.contents.map((b) => b.action.text), ['ยืนยัน', 'ยกเลิก']);
  assert.equal(m.quickReply.items.length, 2);
});

test('รายละเอียดยาวมาก altText ถูกตัดไม่เกิน 1500', () => {
  const m = M.confirmReport({ category: 'X', description: 'ก'.repeat(3000) }, []);
  assert.ok(m.altText.length <= 1500);
});

test('ติดตามงานใช้สีป้ายตามสถานะ', () => {
  const m = M.statusList([
    { ticketNo: 'R1', status: 'REPAIRING', categoryLabel: 'ไฟฟ้า', statusLabel: 'กำลังซ่อม', createdAtText: '-' },
    { ticketNo: 'R2', status: 'COMPLETED', categoryLabel: 'ประปา', statusLabel: 'ซ่อมเสร็จแล้ว', createdAtText: '-' },
  ]);
  const json = JSON.stringify(m.contents);
  assert.match(json, /#DBEAFE/);
  assert.match(json, /#DCFCE7/);
  assert.equal(M.statusList([]).type, 'text');
});

test('แจ้งผลการซ่อมมีรูปหัวการ์ดเมื่อมีรูป และไม่มีเมื่อไม่มีรูป', () => {
  const t = { ticketNo: 'R1', roomNo: 'A1-01', repairResult: 'เปลี่ยนซีล', photoCount: 1, photoDays: 30 };
  assert.equal(M.repairResult(t, 'ประปา', 'https://x/1.jpg').contents.hero.url, 'https://x/1.jpg');
  assert.equal(M.repairResult({ ...t, photoCount: 0 }, 'ประปา').contents.hero, undefined);
});
