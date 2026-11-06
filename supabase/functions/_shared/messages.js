/** ข้อความ LINE ทั้งหมดของระบบ (ถ้อยคำรอทีมยืนยันตาม SRS ฉบับ 15 ต.ค. ภาคผนวก ข) */

export const text = (value) => ({ type: 'text', text: value });

const quickReply = (labels) => ({
  items: labels.map((label) => ({ type: 'action', action: { type: 'message', label, text: label } })),
});

const withQuick = (value, labels) => ({ ...text(value), quickReply: quickReply(labels) });

export function welcome() {
  return text(
    'ยินดีต้อนรับสู่ระบบแจ้งซ่อมหอพัก\n' +
      '1) กด "ผูกเลขห้อง" แล้วพิมพ์รหัส 6 หลักที่ได้รับจากผู้ดูแล\n' +
      '2) กด "แจ้งซ่อม" เพื่อแจ้งปัญหา\n' +
      '3) กด "ติดตามงาน" เพื่อดูสถานะ'
  );
}

export function help() {
  return withQuick('เลือกเมนูที่ต้องการ', ['แจ้งซ่อม', 'ติดตามงาน', 'ผูกเลขห้อง', 'ติดต่อผู้ดูแล']);
}

export function askBindCode() {
  return withQuick('กรุณาพิมพ์รหัสผูกห้อง 6 หลักที่ได้รับจากผู้ดูแลหอพัก', ['ยกเลิก']);
}

export function askCategory(categories) {
  return withQuick('เลือกหมวดปัญหา', [...categories.map((c) => c.label), 'ยกเลิก']);
}

export function askPhoto(max) {
  return withQuick(`ส่งรูปประกอบได้สูงสุด ${max} รูป หรือกด "ข้าม" ถ้าไม่มีรูป`, ['ข้าม', 'ยกเลิก']);
}

export function photoReceived(count, max) {
  return withQuick(`ได้รับรูปแล้ว ${count}/${max} รูป ส่งเพิ่มได้ หรือกด "เสร็จ"`, ['เสร็จ', 'ยกเลิก']);
}

export function confirmReport(draft, categories) {
  const category = categories.find((c) => c.code === draft.category);
  const photos = (draft.photoMessageIds || []).length;
  return withQuick(
    'ตรวจสอบก่อนส่ง\n' +
      `หมวด: ${category ? category.label : '-'}\n` +
      `รายละเอียด: ${draft.description}\n` +
      `รูปภาพ: ${photos} รูป\n\n` +
      'กด "ยืนยัน" เพื่อส่งแจ้งซ่อม',
    ['ยืนยัน', 'ยกเลิก']
  );
}

export function ticketCreated(ticketNo, roomNo) {
  return text(`รับแจ้งซ่อมแล้ว\nเลขที่: ${ticketNo}\nห้อง: ${roomNo}\nสถานะ: รอดำเนินการ\nกด "ติดตามงาน" เพื่อดูสถานะได้ตลอด`);
}

export function reportFailed() {
  return withQuick('ส่งแจ้งซ่อมไม่สำเร็จ ข้อมูลที่กรอกยังอยู่ กด "ยืนยัน" เพื่อลองอีกครั้ง', ['ยืนยัน', 'ยกเลิก']);
}

export function statusList(rows) {
  if (rows.length === 0) return text('ยังไม่มีรายการแจ้งซ่อมของห้องนี้');
  const lines = rows.map((r) => `• ${r.ticketNo} ${r.categoryLabel}\n  ${r.statusLabel} · แจ้งเมื่อ ${r.createdAtText}`);
  return text(`รายการแจ้งซ่อมล่าสุดของห้อง\n\n${lines.join('\n')}`);
}

export function contact(info) {
  return text(info || 'ติดต่อผู้ดูแลหอพักที่สำนักงานหอพัก (ผู้ดูแลยังไม่ได้ตั้งค่าเบอร์ติดต่อ)');
}

export function bindingDone(roomNo) {
  return text(`ผูกบัญชีกับห้อง ${roomNo} เรียบร้อยแล้ว กด "แจ้งซ่อม" เพื่อแจ้งปัญหาได้เลย`);
}

export function bindCodeInvalid() {
  return text('รหัสไม่ถูกต้อง หมดอายุ หรือถูกใช้ไปแล้ว กรุณาขอรหัสใหม่จากผู้ดูแลหอพัก');
}

export function repairResult(ticket, categoryLabel) {
  return text(
    'แจ้งผลการซ่อม\n' +
      `เลขที่: ${ticket.ticketNo}\n` +
      `ห้อง: ${ticket.roomNo}\n` +
      `หมวด: ${categoryLabel}\n` +
      'สถานะ: ซ่อมเสร็จแล้ว\n' +
      `ผลการซ่อม: ${ticket.repairResult || '-'}` +
      (ticket.photoCount ? `\n\nรูปหลังซ่อม ${ticket.photoCount} รูปอยู่ถัดจากข้อความนี้ เปิดดูได้ ${ticket.photoDays} วัน` : '')
  );
}

/** LINE ต้องการลิงก์ HTTPS ที่เปิดได้ตรง ใช้รูปเดียวกันเป็นทั้งรูปเต็มและรูปตัวอย่าง */
export function image(url) {
  return { type: 'image', originalContentUrl: url, previewImageUrl: url };
}
