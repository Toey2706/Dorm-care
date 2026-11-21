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

test('ทุกขั้นที่มีปุ่มเป็นการ์ด ปุ่มในการ์ดตรงกับ quick reply', () => {
  const cats = [{ code: 'PLUMBING', label: 'ประปา' }, { code: 'ELECTRICAL', label: 'ไฟฟ้า' }];
  for (const m of [M.welcome(), M.welcome(true), M.help(), M.help(true), M.askBindCode(), M.askCategory(cats), M.askDetail(), M.askPhoto(3), M.photoReceived(1, 3), M.reportFailed(), M.bindingDone('A1-01')]) {
    assert.equal(m.type, 'flex');
    const inCard = m.contents.footer.contents.map((b) => b.action.text);
    assert.deepEqual(inCard, m.quickReply.items.map((i) => i.action.text));
    assert.ok(texts(m.contents).every((t) => typeof t === 'string' && t.length > 0));
  }
  assert.deepEqual(M.askPhoto(3).contents.footer.contents.map((b) => b.action.text), ['ข้าม', 'ยกเลิก']);
});

test('ยังไม่ผูกห้อง ต้อนรับและเมนูมีแค่ผูกเลขห้องกับติดต่อผู้ดูแล', () => {
  const labels = (m) => m.contents.footer.contents.map((b) => b.action.text);
  assert.deepEqual(labels(M.welcome()), ['ผูกเลขห้อง', 'ติดต่อผู้ดูแล']);
  assert.deepEqual(labels(M.help()), ['ผูกเลขห้อง', 'ติดต่อผู้ดูแล']);
  assert.ok(!labels(M.welcome(true)).includes('ผูกเลขห้อง'));
});

test('การ์ดน้ำ แจ้งซ่อม และติดตามงานแบบใหม่ ไม่มีข้อความว่าง และปุ่มส่งคำสั่งเดิม', () => {
  const days = Array.from({ length: 7 }, (_, i) => ({ date: `2026-11-${15 + i}`, l: i === 3 ? 0 : i * 2.5 }));
  const usage = M.waterUsage('A1-01', { today_l: 15, week_l: 52.5, month_l: 120, at: '2026-11-21T13:00:00Z', days });
  const chart = JSON.stringify(usage.contents);
  assert.match(chart, /วันนี้/);
  assert.equal((chart.match(/"justifyContent":"flex-end"/g) || []).length, 7);
  const alert = M.waterAlert({ roomNo: 'A1-01', minutes: 1.5, flowLpm: 0.5, totalL: 3.2, timeText: '21 พ.ย. 2569 18:29', limit: 1.5 });
  assert.deepEqual(alert.contents.footer.contents.map((b) => b.action.text), ['แจ้งซ่อม', 'ตั้งแจ้งเตือนน้ำ']);
  const list = M.statusList([
    { ticketNo: 'R1', status: 'REPAIRING', categoryLabel: 'ไฟฟ้า', statusLabel: 'กำลังซ่อม', createdAtText: '-' },
    { ticketNo: 'R2', status: 'COMPLETED', categoryLabel: 'ประปา', statusLabel: 'ซ่อมเสร็จแล้ว', createdAtText: '-' },
  ]);
  assert.equal(list.contents.type, 'carousel');
  assert.equal(M.statusList([{ ticketNo: 'R1', status: 'PENDING', categoryLabel: 'ไฟฟ้า', statusLabel: 'รอดำเนินการ', createdAtText: '-' }]).contents.type, 'bubble');
  for (const m of [usage, alert, list, M.waterRules('A1-01', [{ start_min: 540, end_min: 600, minutes: 30 }], 10), M.waterRules('A1-01', [], 0.5), M.ticketCreated('R1', 'A1-01'), M.welcome(), M.welcome(true)]) {
    assert.ok(texts(m.contents).every((t) => typeof t === 'string' && t.length > 0));
  }
  assert.equal(M.waterUsage('A1-01', { today_l: 1, week_l: 1, month_l: 1, at: '2026-11-21T13:00:00Z' }).type, 'flex');
});
