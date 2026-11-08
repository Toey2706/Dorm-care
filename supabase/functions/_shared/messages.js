/** ข้อความ LINE ทั้งหมดของระบบ (ถ้อยคำรอทีมยืนยันตาม SRS ฉบับ 15 ต.ค. ภาคผนวก ข) */

export const text = (value) => ({ type: 'text', text: value });

const quickReply = (labels) => ({
  items: labels.map((label) => ({ type: 'action', action: { type: 'message', label, text: label } })),
});


// สีเดียวกับแอปพนักงาน (app/lib/theme.dart) ผู้พักเห็นสถานะสีเดียวกับที่ผู้ดูแลเห็น
const BRAND = '#1E4E8C';
const INK = '#1B2333';
const MUTED = '#5B6577';
const STATUS = {
  PENDING: { bg: '#FEF3C7', fg: '#8A3B07' },
  REPAIRING: { bg: '#DBEAFE', fg: '#1E3A8A' },
  COMPLETED: { bg: '#DCFCE7', fg: '#14532D' },
};

// LINE จำกัด altText ไม่เกิน 1500 ตัวอักษร รายละเอียดที่ผู้พักพิมพ์ยาวมากจะทำให้ส่งไม่ผ่านทั้งข้อความ
const ALT_MAX = 1500;
const flex = (alt, contents) => ({ type: 'flex', altText: alt.length > ALT_MAX ? alt.slice(0, ALT_MAX - 1) + '…' : alt, contents });

const bubble = ({ header: head, body, footer }) => {
  const b = { type: 'bubble', body: { type: 'box', layout: 'vertical', spacing: 'md', paddingAll: '16px', contents: body } };
  if (head) b.header = head;
  if (footer) b.footer = { type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '12px', contents: footer };
  return b;
};

const header = (title, subtitle) => ({
  type: 'box',
  layout: 'vertical',
  backgroundColor: BRAND,
  paddingAll: '16px',
  contents: [
    { type: 'text', text: title, color: '#FFFFFFD9', size: 'sm' },
    { type: 'text', text: subtitle, color: '#FFFFFF', size: 'xl', weight: 'bold' },
  ],
});

const row = (label, value) => ({
  type: 'box',
  layout: 'horizontal',
  spacing: 'md',
  contents: [
    { type: 'text', text: label, size: 'sm', color: MUTED, flex: 2 },
    { type: 'text', text: String(value || '-'), size: 'sm', color: INK, flex: 5, wrap: true },
  ],
});

// flex 0 ให้ป้ายกว้างเท่าข้อความ ไม่ยืดเต็มแถว
const badge = (style, label) => ({
  type: 'box',
  layout: 'vertical',
  flex: 0,
  backgroundColor: style.bg,
  cornerRadius: '12px',
  paddingStart: '10px',
  paddingEnd: '10px',
  paddingTop: '3px',
  paddingBottom: '3px',
  contents: [{ type: 'text', text: label, size: 'xs', weight: 'bold', color: style.fg }],
});

const badgeLine = (style, label) => ({ type: 'box', layout: 'horizontal', contents: [badge(style, label), { type: 'filler' }] });

// ปุ่มส่งข้อความเดียวกับที่ผู้พักพิมพ์เอง บทสนทนาจึงทำงานเหมือนเดิมไม่ต้องแก้ส่วนจัดการสถานะ
const button = (label, style) => ({
  type: 'button',
  style,
  height: 'sm',
  color: style === 'primary' ? BRAND : undefined,
  action: { type: 'message', label, text: label },
});

/**
 * การ์ดคำถามแต่ละขั้น ปุ่มในการ์ดกับ quick reply ส่งข้อความเดียวกัน
 * LINE คอมพิวเตอร์ไม่แสดง quick reply ผู้ใช้บนคอมจึงกดปุ่มในการ์ดแทนได้
 */
function card(alt, { title, subtitle, lines = [], buttons }) {
  const body = lines.map((l) => ({ type: 'text', text: l, size: 'sm', color: INK, wrap: true }));
  const b = bubble({ header: header(title, subtitle), body: body.length ? body : [{ type: 'filler' }], footer: buttons.map(([l, st]) => button(l, st)) });
  if (!body.length) delete b.body;
  return { ...flex(alt, b), quickReply: quickReply(buttons.map(([l]) => l)) };
}

export function welcome() {
  const alt =
    'ยินดีต้อนรับสู่ระบบแจ้งซ่อมหอพัก\n' +
    '1) กด "ผูกเลขห้อง" แล้วพิมพ์รหัส 6 หลักที่ได้รับจากผู้ดูแล\n' +
    '2) กด "แจ้งซ่อม" เพื่อแจ้งปัญหา\n' +
    '3) กด "ติดตามงาน" เพื่อดูสถานะ';
  return card(alt, {
    title: 'ยินดีต้อนรับ',
    subtitle: 'ระบบแจ้งซ่อมหอพัก',
    lines: ['1) กด "ผูกเลขห้อง" แล้วพิมพ์รหัส 6 หลักที่ได้รับจากผู้ดูแล', '2) กด "แจ้งซ่อม" เพื่อแจ้งปัญหา', '3) กด "ติดตามงาน" เพื่อดูสถานะ'],
    buttons: [['ผูกเลขห้อง', 'primary'], ['แจ้งซ่อม', 'secondary'], ['ติดตามงาน', 'secondary']],
  });
}

export function help() {
  return card('เลือกเมนูที่ต้องการ', {
    title: 'เมนู',
    subtitle: 'เลือกเมนูที่ต้องการ',
    buttons: [['แจ้งซ่อม', 'primary'], ['ติดตามงาน', 'secondary'], ['ผูกเลขห้อง', 'secondary'], ['ติดต่อผู้ดูแล', 'secondary']],
  });
}

export function askBindCode() {
  return card('กรุณาพิมพ์รหัสผูกห้อง 6 หลักที่ได้รับจากผู้ดูแลหอพัก', {
    title: 'ผูกเลขห้อง',
    subtitle: 'พิมพ์รหัส 6 หลัก',
    lines: ['พิมพ์รหัสผูกห้อง 6 หลักที่ได้รับจากผู้ดูแลหอพักลงในช่องแชต'],
    buttons: [['ยกเลิก', 'link']],
  });
}

export function askCategory(categories) {
  return card('เลือกหมวดปัญหา', {
    title: 'แจ้งซ่อม ขั้นที่ 1 จาก 4',
    subtitle: 'เลือกหมวดปัญหา',
    buttons: [...categories.map((c) => [c.label, 'secondary']), ['ยกเลิก', 'link']],
  });
}

export function askDetail() {
  return card('กรุณาพิมพ์รายละเอียดปัญหา เช่น ตำแหน่งและอาการที่พบ\n(พิมพ์ "ยกเลิก" เพื่อยกเลิก)', {
    title: 'แจ้งซ่อม ขั้นที่ 2 จาก 4',
    subtitle: 'พิมพ์รายละเอียดปัญหา',
    lines: ['พิมพ์ลงในช่องแชต บอกตำแหน่งและอาการที่พบ เช่น ก๊อกอ่างล้างหน้ารั่ว น้ำหยดตลอด'],
    buttons: [['ยกเลิก', 'link']],
  });
}

export function askPhoto(max) {
  return card(`ส่งรูปประกอบได้สูงสุด ${max} รูป หรือกด "ข้าม" ถ้าไม่มีรูป`, {
    title: 'แจ้งซ่อม ขั้นที่ 3 จาก 4',
    subtitle: 'ส่งรูปประกอบ',
    lines: [`ส่งรูปได้สูงสุด ${max} รูป ถ้าไม่มีรูปกด "ข้าม"`],
    buttons: [['ข้าม', 'secondary'], ['ยกเลิก', 'link']],
  });
}

export function photoReceived(count, max) {
  return card(`ได้รับรูปแล้ว ${count}/${max} รูป ส่งเพิ่มได้ หรือกด "เสร็จ"`, {
    title: 'แจ้งซ่อม ขั้นที่ 3 จาก 4',
    subtitle: `ได้รับรูปแล้ว ${count}/${max}`,
    lines: ['ส่งรูปเพิ่มได้ หรือกด "เสร็จ" เพื่อไปขั้นถัดไป'],
    buttons: [['เสร็จ', 'primary'], ['ยกเลิก', 'link']],
  });
}

export function confirmReport(draft, categories) {
  const category = categories.find((c) => c.code === draft.category);
  const categoryText = category ? category.label : '-';
  const photos = (draft.photoMessageIds || []).length;
  const alt =
    'ตรวจสอบก่อนส่ง\n' +
    `หมวด: ${categoryText}\n` +
    `รายละเอียด: ${draft.description}\n` +
    `รูปภาพ: ${photos} รูป\n\n` +
    'กด "ยืนยัน" เพื่อส่งแจ้งซ่อม';
  const card = bubble({
    header: header('แจ้งซ่อม ขั้นที่ 4 จาก 4', 'ตรวจสอบก่อนส่ง'),
    body: [row('หมวด', categoryText), row('รายละเอียด', draft.description), row('รูปภาพ', `${photos} รูป`)],
    footer: [button('ยืนยัน', 'primary'), button('ยกเลิก', 'link')],
  });
  // quick reply ยังคงไว้ เพราะผู้ใช้บางคนคุ้นกับปุ่มด้านล่าง ส่วนปุ่มในการ์ดใช้ได้บน LINE คอมพิวเตอร์ที่ไม่มี quick reply
  return { ...flex(alt, card), quickReply: quickReply(['ยืนยัน', 'ยกเลิก']) };
}

/** details เป็นข้อมูลจากร่างแจ้งซ่อม ไม่บังคับ ถ้าไม่มีการ์ดจะแสดงเฉพาะเลขที่กับห้อง */
export function ticketCreated(ticketNo, roomNo, details = {}) {
  const alt = `รับแจ้งซ่อมแล้ว\nเลขที่: ${ticketNo}\nห้อง: ${roomNo}\nสถานะ: รอดำเนินการ\nกด "ติดตามงาน" เพื่อดูสถานะได้ตลอด`;
  const rows = [row('ห้อง', roomNo)];
  if (details.categoryLabel) rows.push(row('หมวด', details.categoryLabel));
  if (details.description) rows.push(row('รายละเอียด', details.description));
  if (details.createdAtText) rows.push(row('แจ้งเมื่อ', details.createdAtText));
  return flex(
    alt,
    bubble({
      header: header('รับแจ้งซ่อมแล้ว', ticketNo),
      body: [badgeLine(STATUS.PENDING, 'รอดำเนินการ'), ...rows],
      footer: [button('ติดตามงาน', 'secondary')],
    })
  );
}

export function reportFailed() {
  return card('ส่งแจ้งซ่อมไม่สำเร็จ ข้อมูลที่กรอกยังอยู่ กด "ยืนยัน" เพื่อลองอีกครั้ง', {
    title: 'ส่งไม่สำเร็จ',
    subtitle: 'ลองอีกครั้ง',
    lines: ['ข้อมูลที่กรอกยังอยู่ กด "ยืนยัน" เพื่อส่งอีกครั้ง'],
    buttons: [['ยืนยัน', 'primary'], ['ยกเลิก', 'link']],
  });
}

export function statusList(rows) {
  if (rows.length === 0) return text('ยังไม่มีรายการแจ้งซ่อมของห้องนี้');
  const lines = rows.map((r) => `• ${r.ticketNo} ${r.categoryLabel}\n  ${r.statusLabel} · แจ้งเมื่อ ${r.createdAtText}`);
  const alt = `รายการแจ้งซ่อมล่าสุดของห้อง\n\n${lines.join('\n')}`;
  const items = [];
  rows.forEach((r, i) => {
    if (i > 0) items.push({ type: 'separator', margin: 'lg', color: '#E3E8EF' });
    items.push({
      type: 'box',
      layout: 'vertical',
      spacing: 'xs',
      margin: i > 0 ? 'lg' : 'none',
      contents: [
        {
          type: 'box',
          layout: 'horizontal',
          contents: [
            { type: 'text', text: r.ticketNo, weight: 'bold', size: 'md', color: INK, flex: 1, gravity: 'center' },
            badge(STATUS[r.status] || STATUS.PENDING, r.statusLabel),
          ],
        },
        { type: 'text', text: r.categoryLabel, size: 'sm', color: INK, wrap: true },
        { type: 'text', text: `แจ้งเมื่อ ${r.createdAtText}`, size: 'xs', color: MUTED },
      ],
    });
  });
  return flex(alt, bubble({ header: header('รายการแจ้งซ่อมล่าสุด', 'ของห้องคุณ'), body: items }));
}

export function contact(info) {
  return text(info || 'ติดต่อผู้ดูแลหอพักที่สำนักงานหอพัก (ผู้ดูแลยังไม่ได้ตั้งค่าเบอร์ติดต่อ)');
}

export function bindingDone(roomNo) {
  return card(`ผูกบัญชีกับห้อง ${roomNo} เรียบร้อยแล้ว กด "แจ้งซ่อม" เพื่อแจ้งปัญหาได้เลย`, {
    title: 'ผูกเลขห้องเรียบร้อย',
    subtitle: `ห้อง ${roomNo}`,
    lines: ['กด "แจ้งซ่อม" เพื่อแจ้งปัญหาได้เลย'],
    buttons: [['แจ้งซ่อม', 'primary'], ['ติดตามงาน', 'secondary']],
  });
}

export function bindCodeInvalid() {
  return text('รหัสไม่ถูกต้อง หมดอายุ หรือถูกใช้ไปแล้ว กรุณาขอรหัสใหม่จากผู้ดูแลหอพัก');
}

/** heroUrl คือรูปหลังซ่อมรูปแรก ใช้เป็นภาพหัวการ์ด รูปเต็มทุกรูปยังส่งตามมาเป็นข้อความรูปภาพ */
export function repairResult(ticket, categoryLabel, heroUrl) {
  const alt =
    'แจ้งผลการซ่อม\n' +
    `เลขที่: ${ticket.ticketNo}\n` +
    `ห้อง: ${ticket.roomNo}\n` +
    `หมวด: ${categoryLabel}\n` +
    'สถานะ: ซ่อมเสร็จแล้ว\n' +
    `ผลการซ่อม: ${ticket.repairResult || '-'}` +
    (ticket.photoCount ? `\n\nรูปหลังซ่อม ${ticket.photoCount} รูปอยู่ถัดจากข้อความนี้ เปิดดูได้ ${ticket.photoDays} วัน` : '');
  const body = [
    {
      type: 'box',
      layout: 'horizontal',
      contents: [
        { type: 'text', text: 'ซ่อมเสร็จแล้ว', weight: 'bold', size: 'lg', color: INK, flex: 1, gravity: 'center' },
        badge(STATUS.COMPLETED, ticket.ticketNo),
      ],
    },
    row('ห้อง', ticket.roomNo),
    row('หมวด', categoryLabel),
    row('ผลการซ่อม', ticket.repairResult || '-'),
  ];
  if (ticket.photoCount) {
    body.push({
      type: 'text',
      text: `รูปหลังซ่อม ${ticket.photoCount} รูปอยู่ถัดจากการ์ดนี้ เปิดดูได้ ${ticket.photoDays} วัน`,
      size: 'xs',
      color: MUTED,
      wrap: true,
      margin: 'md',
    });
  }
  const card = bubble({ body });
  if (heroUrl) {
    card.hero = { type: 'image', url: heroUrl, size: 'full', aspectRatio: '20:13', aspectMode: 'cover', action: { type: 'uri', label: 'ดูรูป', uri: heroUrl } };
  }
  return flex(alt, card);
}

/** LINE ต้องการลิงก์ HTTPS ที่เปิดได้ตรง ใช้รูปเดียวกันเป็นทั้งรูปเต็มและรูปตัวอย่าง */
export function image(url) {
  return { type: 'image', originalContentUrl: url, previewImageUrl: url };
}
