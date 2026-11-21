/** ข้อความ LINE ทั้งหมดของระบบ (ถ้อยคำรอทีมยืนยันตาม SRS ฉบับ 15 ต.ค. ภาคผนวก ข) */

export const text = (value) => ({ type: 'text', text: value });

const quickReply = (labels) => ({
  items: labels.map((label) => ({ type: 'action', action: { type: 'message', label, text: label } })),
});


// สีเดียวกับแอปพนักงาน (app/lib/theme.dart) ผู้พักเห็นสถานะสีเดียวกับที่ผู้ดูแลเห็น
const BRAND = '#1E4E8C';
const BRAND_LIGHT = '#2F6DB5';
const TINT = '#EAF1FA';
const LINE_GRAY = '#E3E8EF';
const INK = '#1B2333';
const MUTED = '#5B6577';
const WARN = { bg: '#FEF3C7', fg: '#8A3B07' };
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

const stepBar = (done, total, color, rest) => ({
  type: 'box',
  layout: 'horizontal',
  spacing: 'xs',
  margin: 'md',
  contents: Array.from({ length: total }, (_, i) => ({
    type: 'box',
    layout: 'vertical',
    height: '6px',
    cornerRadius: '3px',
    backgroundColor: i < done ? color : rest,
    contents: [],
  })),
});

const header = (title, subtitle, step = null) => ({
  type: 'box',
  layout: 'vertical',
  paddingAll: '16px',
  background: { type: 'linearGradient', angle: '135deg', startColor: BRAND, endColor: BRAND_LIGHT },
  contents: [
    { type: 'text', text: title, color: '#FFFFFFCC', size: 'xs', weight: 'bold' },
    { type: 'text', text: subtitle, color: '#FFFFFF', size: 'xl', weight: 'bold', wrap: true, margin: 'xs' },
    ...(step ? [stepBar(step.n, step.of, '#FFFFFF', '#FFFFFF4D')] : []),
  ],
});

const STEPS = [
  ['PENDING', 'รับเรื่อง'],
  ['REPAIRING', 'กำลังซ่อม'],
  ['COMPLETED', 'ซ่อมเสร็จ'],
];

const progress = (status) => {
  const at = Math.max(0, STEPS.findIndex(([code]) => code === status));
  return {
    type: 'box',
    layout: 'vertical',
    spacing: 'sm',
    margin: 'md',
    contents: [
      stepBar(at + 1, STEPS.length, BRAND, LINE_GRAY),
      {
        type: 'box',
        layout: 'horizontal',
        contents: STEPS.map(([, label], i) => ({
          type: 'text',
          text: label,
          size: 'xxs',
          align: i === 0 ? 'start' : i === STEPS.length - 1 ? 'end' : 'center',
          color: i === at ? BRAND : i < at ? INK : MUTED,
          weight: i === at ? 'bold' : 'regular',
        })),
      },
    ],
  };
};

const tile = (label, value, flexValue = 1) => ({
  type: 'box',
  layout: 'vertical',
  flex: flexValue,
  backgroundColor: TINT,
  cornerRadius: '12px',
  paddingAll: '10px',
  contents: [
    { type: 'text', text: label, size: 'xxs', color: MUTED },
    { type: 'text', text: value, size: 'md', weight: 'bold', color: INK, wrap: true },
  ],
});

const note = (value, style = WARN) => ({
  type: 'box',
  layout: 'vertical',
  backgroundColor: style.bg,
  cornerRadius: '10px',
  paddingAll: '10px',
  margin: 'md',
  contents: [{ type: 'text', text: value, size: 'xs', color: style.fg, wrap: true }],
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
const button = (label, style, sendText = label) => ({
  type: 'button',
  style,
  height: 'sm',
  color: style === 'primary' ? BRAND : undefined,
  action: { type: 'message', label, text: sendText },
});

/**
 * การ์ดคำถามแต่ละขั้น ปุ่มในการ์ดกับ quick reply ส่งข้อความเดียวกัน
 * LINE คอมพิวเตอร์ไม่แสดง quick reply ผู้ใช้บนคอมจึงกดปุ่มในการ์ดแทนได้
 */
const numbered = (items) => ({
  type: 'box',
  layout: 'vertical',
  spacing: 'md',
  contents: items.map((value, i) => ({
    type: 'box',
    layout: 'horizontal',
    spacing: 'md',
    contents: [
      {
        type: 'box',
        layout: 'vertical',
        width: '22px',
        height: '22px',
        cornerRadius: '11px',
        backgroundColor: BRAND,
        justifyContent: 'center',
        contents: [{ type: 'text', text: String(i + 1), size: 'xs', color: '#FFFFFF', weight: 'bold', align: 'center' }],
      },
      { type: 'text', text: value, size: 'sm', color: INK, wrap: true, flex: 1, gravity: 'center' },
    ],
  })),
});

function card(alt, { title, subtitle, lines = [], extra = [], buttons, step = null }) {
  const body = [...lines.map((l) => ({ type: 'text', text: l, size: 'sm', color: INK, wrap: true })), ...extra];
  const b = bubble({ header: header(title, subtitle, step), body: body.length ? body : [{ type: 'filler' }], footer: buttons.map(([l, st]) => button(l, st)) });
  if (!body.length) delete b.body;
  return { ...flex(alt, b), quickReply: quickReply(buttons.map(([l]) => l)) };
}

/** ผู้ที่ยังไม่ผูกห้องใช้ได้แค่ผูกเลขห้องกับติดต่อผู้ดูแล จึงแสดงเฉพาะสองปุ่มนี้ ลดการกดแจ้งซ่อมแล้วโดนปฏิเสธ */
export function welcome(bound = false) {
  if (!bound) {
    const alt =
      'ยินดีต้อนรับสู่ระบบแจ้งซ่อมหอพัก\n' +
      'กด "ผูกเลขห้อง" แล้วพิมพ์รหัส 6 หลักที่ได้รับจากผู้ดูแล เพื่อเริ่มใช้งาน\n' +
      'ยังไม่มีรหัส กด "ติดต่อผู้ดูแล"';
    return card(alt, {
      title: 'ยินดีต้อนรับ',
      subtitle: 'ระบบแจ้งซ่อมหอพัก',
      extra: [
        { type: 'text', text: 'เริ่มใช้งานใน 2 ขั้น', size: 'sm', weight: 'bold', color: BRAND },
        numbered(['ขอรหัส 6 หลักจากผู้ดูแลหอพัก', 'กด "ผูกเลขห้อง" แล้วพิมพ์รหัสลงในแชต']),
        note('ผูกห้องแล้วแจ้งซ่อม ติดตามงาน และรับแจ้งผลการซ่อมผ่าน LINE ได้ทันที', { bg: TINT, fg: BRAND }),
      ],
      buttons: [['ผูกเลขห้อง', 'primary'], ['ติดต่อผู้ดูแล', 'secondary']],
    });
  }
  return card('ยินดีต้อนรับกลับสู่ระบบแจ้งซ่อมหอพัก\nกด "แจ้งซ่อม" เพื่อแจ้งปัญหา หรือ "ติดตามงาน" เพื่อดูสถานะ', {
    title: 'ยินดีต้อนรับกลับ',
    subtitle: 'ระบบแจ้งซ่อมหอพัก',
    extra: [
      { type: 'text', text: 'บัญชีนี้ผูกห้องไว้แล้ว ใช้เมนูด้านล่างได้เลย', size: 'sm', color: INK, wrap: true },
      numbered(['"แจ้งซ่อม" เลือกหมวด พิมพ์อาการ แนบรูปได้', '"ติดตามงาน" ดูว่างานถึงขั้นไหนแล้ว', 'ซ่อมเสร็จ ระบบแจ้งผลกลับมาทางแชตนี้']),
    ],
    buttons: [['แจ้งซ่อม', 'primary'], ['ติดตามงาน', 'secondary'], ['ติดต่อผู้ดูแล', 'secondary']],
  });
}

export function help(bound = false) {
  const buttons = bound
    ? [['แจ้งซ่อม', 'primary'], ['ติดตามงาน', 'secondary'], ['ติดต่อผู้ดูแล', 'secondary']]
    : [['ผูกเลขห้อง', 'primary'], ['ติดต่อผู้ดูแล', 'secondary']];
  return card('เลือกเมนูที่ต้องการ', { title: 'เมนู', subtitle: 'เลือกเมนูที่ต้องการ', buttons });
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
    step: { n: 1, of: 4 },
    buttons: [...categories.map((c) => [c.label, 'secondary']), ['ยกเลิก', 'link']],
  });
}

export function askDetail() {
  return card('กรุณาพิมพ์รายละเอียดปัญหา เช่น ตำแหน่งและอาการที่พบ\n(พิมพ์ "ยกเลิก" เพื่อยกเลิก)', {
    title: 'แจ้งซ่อม ขั้นที่ 2 จาก 4',
    subtitle: 'พิมพ์รายละเอียดปัญหา',
    step: { n: 2, of: 4 },
    lines: ['พิมพ์ลงในช่องแชต บอกตำแหน่งและอาการที่พบ เช่น ก๊อกอ่างล้างหน้ารั่ว น้ำหยดตลอด'],
    buttons: [['ยกเลิก', 'link']],
  });
}

export function askPhoto(max) {
  return card(`ส่งรูปประกอบได้สูงสุด ${max} รูป หรือกด "ข้าม" ถ้าไม่มีรูป`, {
    title: 'แจ้งซ่อม ขั้นที่ 3 จาก 4',
    subtitle: 'ส่งรูปประกอบ',
    step: { n: 3, of: 4 },
    lines: [`ส่งรูปได้สูงสุด ${max} รูป ถ้าไม่มีรูปกด "ข้าม"`],
    buttons: [['ข้าม', 'secondary'], ['ยกเลิก', 'link']],
  });
}

export function photoReceived(count, max) {
  return card(`ได้รับรูปแล้ว ${count}/${max} รูป ส่งเพิ่มได้ หรือกด "เสร็จ"`, {
    title: 'แจ้งซ่อม ขั้นที่ 3 จาก 4',
    subtitle: `ได้รับรูปแล้ว ${count}/${max}`,
    step: { n: 3, of: 4 },
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
    header: header('แจ้งซ่อม ขั้นที่ 4 จาก 4', 'ตรวจสอบก่อนส่ง', { n: 4, of: 4 }),
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
      body: [badgeLine(STATUS.PENDING, 'รอดำเนินการ'), ...rows, progress('PENDING'), note('ผู้ดูแลจะมอบหมายช่างให้ และแจ้งผลทาง LINE เมื่อซ่อมเสร็จ', { bg: TINT, fg: BRAND })],
      footer: [button('ดูสถานะงานซ่อม', 'secondary', 'ติดตามงาน')],
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
  const bubbles = rows.map((r) => ({
    type: 'bubble',
    size: 'kilo',
    body: {
      type: 'box',
      layout: 'vertical',
      spacing: 'sm',
      paddingAll: '16px',
      contents: [
        {
          type: 'box',
          layout: 'horizontal',
          contents: [
            { type: 'text', text: r.ticketNo, weight: 'bold', size: 'md', color: INK, flex: 1, gravity: 'center' },
            badge(STATUS[r.status] || STATUS.PENDING, r.statusLabel),
          ],
        },
        { type: 'text', text: r.categoryLabel, size: 'lg', weight: 'bold', color: BRAND, wrap: true, margin: 'md' },
        { type: 'text', text: `แจ้งเมื่อ ${r.createdAtText}`, size: 'xs', color: MUTED, wrap: true },
        progress(r.status),
      ],
    },
  }));
  return flex(alt, bubbles.length === 1 ? bubbles[0] : { type: 'carousel', contents: bubbles });
}

export function contact(info) {
  return text(info || 'ติดต่อผู้ดูแลหอพักที่สำนักงานหอพัก (ผู้ดูแลยังไม่ได้ตั้งค่าเบอร์ติดต่อ)');
}

export function bindingDone(roomNo) {
  return card(`ผูกบัญชีกับห้อง ${roomNo} เรียบร้อยแล้ว กด "แจ้งซ่อม" เพื่อแจ้งปัญหาได้เลย`, {
    title: 'ผูกเลขห้องเรียบร้อย',
    subtitle: `ห้อง ${roomNo}`,
    lines: ['เมนูด้านล่างเปลี่ยนเป็นเมนูของห้องแล้ว กด "แจ้งซ่อม" เพื่อแจ้งปัญหาได้เลย'],
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
    progress('COMPLETED'),
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

export function durationText(minutes) {
  const total = Math.round(Number(minutes) * 60);
  const m = Math.floor(total / 60);
  const sec = total % 60;
  if (m && sec) return `${m} นาที ${sec} วินาที`;
  return m ? `${m} นาที` : `${sec} วินาที`;
}

export function waterAlert({ roomNo, minutes, flowLpm, totalL, timeText, test = false, limit = null }) {
  const title = test ? 'ทดสอบการแจ้งเตือน' : 'น้ำไหลต่อเนื่องผิดปกติ';
  const alt =
    `แจ้งเตือนจากอุปกรณ์วัดน้ำ ห้อง ${roomNo}\n` +
    `${title} ไหลต่อเนื่อง ${durationText(minutes)} อัตราไหล ${flowLpm} L/min\n` +
    'ถ้าไม่ได้เปิดน้ำใช้อยู่ อาจลืมปิดน้ำหรือมีท่อรั่ว';
  const body = [
    { type: 'text', text: `ห้อง ${roomNo} · ${timeText}`, size: 'xs', color: MUTED, wrap: true },
    { type: 'text', text: 'น้ำไหลต่อเนื่องมาแล้ว', size: 'sm', color: INK, margin: 'md' },
    { type: 'text', text: durationText(minutes), size: '3xl', weight: 'bold', color: BRAND, wrap: true },
    {
      type: 'box',
      layout: 'horizontal',
      spacing: 'sm',
      margin: 'md',
      contents: [tile('อัตราไหล', `${flowLpm} L/min`), tile('ปริมาณรวม', `${totalL} L`)],
    },
  ];
  if (limit) body.push({ type: 'text', text: `ตั้งไว้ให้เตือนเมื่อไหลเกิน ${durationText(limit)}`, size: 'xs', color: MUTED, wrap: true, margin: 'md' });
  body.push(note('ถ้าไม่ได้เปิดน้ำใช้อยู่ อาจลืมปิดน้ำหรือมีท่อรั่ว ลองตรวจก๊อกและชักโครกในห้อง'));
  const b = bubble({
    header: header('แจ้งเตือนจากอุปกรณ์วัดน้ำ', title),
    body,
    footer: [button('แจ้งซ่อมท่อหรือก๊อกรั่ว', 'primary', 'แจ้งซ่อม'), button('ปรับเวลาแจ้งเตือน', 'secondary', 'ตั้งแจ้งเตือนน้ำ')],
  });
  return { ...flex(alt, b), quickReply: quickReply(['แจ้งซ่อม', 'ตั้งแจ้งเตือนน้ำ', 'ติดต่อผู้ดูแล']) };
}

const hhmm = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

const deleteChip = (id, when) => ({
  type: 'box',
  layout: 'vertical',
  flex: 0,
  justifyContent: 'center',
  backgroundColor: '#FFFFFF',
  borderColor: '#D5DBE5',
  borderWidth: '1px',
  cornerRadius: '14px',
  paddingStart: '10px',
  paddingEnd: '10px',
  paddingTop: '4px',
  paddingBottom: '4px',
  action: { type: 'postback', label: 'ลบ', data: `water:del:${id}`, displayText: `ลบช่วงเวลา ${when}` },
  contents: [{ type: 'text', text: 'ลบ', size: 'xs', color: '#B42318', weight: 'bold' }],
});

const ruleRow = (when, value, id = null) => ({
  type: 'box',
  layout: 'horizontal',
  spacing: 'md',
  backgroundColor: TINT,
  cornerRadius: '12px',
  paddingAll: '12px',
  contents: [
    { type: 'text', text: when, size: 'sm', weight: 'bold', color: INK, flex: 4, wrap: true, gravity: 'center' },
    { type: 'text', text: value, size: 'sm', color: BRAND, weight: 'bold', align: 'end', flex: 3, wrap: true, gravity: 'center' },
    ...(id ? [deleteChip(id, when)] : []),
  ],
});

export function waterRules(roomNo, rules, defaultMinutes = 10) {
  const lines = rules.length
    ? rules.map((r) => `${hhmm(r.start_min)}-${hhmm(r.end_min)} เตือนเมื่อไหลเกิน ${durationText(r.minutes)}`)
    : ['ยังไม่ได้ตั้งช่วงเวลา'];
  lines.push(`${rules.length ? 'เวลาอื่น' : 'ทั้งวัน'}เตือนเมื่อน้ำไหลต่อเนื่องเกิน ${durationText(defaultMinutes)}`);
  const buttons = rules.length
    ? [['ตั้งเวลาแจ้งเตือน', 'primary'], ['ลบช่วงเวลาทั้งหมด', 'secondary']]
    : [['ตั้งเวลาแจ้งเตือน', 'primary']];
  const extra = [
    { type: 'text', text: 'เตือนเมื่อน้ำไหลต่อเนื่องนานเกิน', size: 'xs', color: MUTED },
    ...rules.map((r) => ruleRow(`${hhmm(r.start_min)}-${hhmm(r.end_min)}`, durationText(r.minutes), r.id)),
    ruleRow(rules.length ? 'เวลาอื่น' : 'ทั้งวัน', durationText(defaultMinutes)),
  ];
  if (!rules.length) extra.push({ type: 'text', text: 'ตั้งเพิ่มเฉพาะช่วงได้ เช่น ช่วงอาบน้ำ 09:00-10:00 ให้นานขึ้น', size: 'xs', color: MUTED, wrap: true });
  else extra.push({ type: 'text', text: 'กด "ลบ" ท้ายช่วงที่ไม่ใช้แล้ว', size: 'xs', color: MUTED, wrap: true });
  return card(`ตั้งแจ้งเตือนน้ำ ห้อง ${roomNo}\n${lines.join('\n')}`, { title: `ตั้งแจ้งเตือนน้ำ ห้อง ${roomNo}`, subtitle: 'เวลาที่ตั้งไว้', extra, buttons });
}

const liters = (v) => `${Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} ลิตร`;

const DAY_NAMES = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

function usageChart(days) {
  const max = Math.max(...days.map((d) => d.l), 0.1);
  return {
    type: 'box',
    layout: 'horizontal',
    spacing: 'sm',
    margin: 'lg',
    contents: days.map((d, i) => {
      const last = i === days.length - 1;
      const h = Math.max(4, Math.round((d.l / max) * 72));
      return {
        type: 'box',
        layout: 'vertical',
        spacing: 'xs',
        contents: [
          { type: 'text', text: d.l ? String(d.l >= 100 ? Math.round(d.l) : d.l) : '0', size: 'xxs', color: last ? BRAND : MUTED, align: 'center', weight: last ? 'bold' : 'regular' },
          {
            type: 'box',
            layout: 'vertical',
            height: '72px',
            justifyContent: 'flex-end',
            contents: [{ type: 'box', layout: 'vertical', height: `${h}px`, cornerRadius: '4px', backgroundColor: last ? BRAND : '#B9CDE6', contents: [] }],
          },
          { type: 'text', text: last ? 'วันนี้' : DAY_NAMES[new Date(`${d.date}T12:00:00Z`).getUTCDay()], size: 'xxs', color: last ? BRAND : MUTED, align: 'center', weight: last ? 'bold' : 'regular' },
        ],
      };
    }),
  };
}

export function waterUsage(roomNo, usage) {
  const at = new Date(usage.at).toLocaleTimeString('th-TH', { timeZone: 'Asia/Bangkok', hour: '2-digit', minute: '2-digit' });
  const items = [
    ['วันนี้', usage.today_l],
    ['7 วัน', usage.week_l],
    ['30 วัน', usage.month_l],
  ];
  const alt = `การใช้น้ำ ห้อง ${roomNo} (ถึง ${at} น.)\n${items.map(([l, v]) => `${l} ${liters(v)}`).join('\n')}`;
  const body = [
    { type: 'text', text: `วันนี้ ตั้งแต่เที่ยงคืนถึง ${at} น.`, size: 'xs', color: MUTED },
    {
      type: 'box',
      layout: 'baseline',
      spacing: 'sm',
      contents: [
        { type: 'text', text: Number(usage.today_l || 0).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 }), size: '3xl', weight: 'bold', color: BRAND, flex: 0 },
        { type: 'text', text: 'ลิตร', size: 'md', color: MUTED, flex: 0 },
      ],
    },
  ];
  if (Array.isArray(usage.days) && usage.days.length) body.push(usageChart(usage.days));
  body.push({
    type: 'box',
    layout: 'horizontal',
    spacing: 'sm',
    margin: 'lg',
    contents: [tile('7 วันล่าสุด', liters(usage.week_l)), tile('30 วันล่าสุด', liters(usage.month_l))],
  });
  body.push({ type: 'text', text: '7 วันและ 30 วันนับรวมวันนี้', size: 'xxs', color: MUTED, wrap: true });
  const b = bubble({ header: header(`การใช้น้ำ ห้อง ${roomNo}`, 'ปริมาณน้ำที่ใช้'), body });
  return { ...flex(alt, b), quickReply: quickReply(['ดูการใช้น้ำ', 'ตั้งแจ้งเตือนน้ำ']) };
}

export function askWaterMode() {
  return card('ตั้งเวลาแจ้งเตือนน้ำ เลือก เฉพาะช่วงเวลา หรือ ทั้งวัน', {
    title: 'ตั้งเวลาแจ้งเตือน',
    subtitle: 'ตั้งแบบไหน',
    lines: [
      'เฉพาะช่วงเวลา: เลือกเวลาเริ่ม เวลาสิ้นสุด แล้วเลือกว่าน้ำไหลเกินกี่นาทีจึงเตือน',
      'ทั้งวัน: เลือกว่าเวลาอื่นทั้งหมด น้ำไหลเกินกี่นาทีจึงเตือน',
    ],
    buttons: [['เฉพาะช่วงเวลา', 'primary'], ['ทั้งวัน', 'secondary'], ['ยกเลิก', 'link']],
  });
}

const timePicker = (label, data, initial, extra = {}) => ({ type: 'datetimepicker', label, data, mode: 'time', initial, ...extra });

export function askWaterTime(which, startMin = null) {
  const isStart = which === 'start';
  const label = isStart ? 'เลือกเวลาเริ่ม' : 'เลือกเวลาสิ้นสุด';
  const initial = isStart ? '09:00' : hhmm(((startMin ?? 540) + 60) % 1440);
  const action = timePicker(label, isStart ? 'water:start' : 'water:end', initial);
  const lines = isStart ? ['กดปุ่มด้านล่างเพื่อเลือกเวลาเริ่ม'] : [`เวลาเริ่ม ${hhmm(startMin)}`, 'กดปุ่มด้านล่างเพื่อเลือกเวลาสิ้นสุด'];
  const b = bubble({
    header: header('ตั้งเวลาแจ้งเตือน', label),
    body: lines.map((l) => ({ type: 'text', text: l, size: 'sm', color: INK, wrap: true })),
    footer: [
      { type: 'button', style: 'primary', height: 'sm', color: BRAND, action },
      button('ยกเลิก', 'link'),
    ],
  });
  return {
    ...flex(`${label} (กดปุ่มในข้อความเพื่อเลือกเวลา)`, b),
    quickReply: { items: [{ type: 'action', action }, { type: 'action', action: { type: 'message', label: 'ยกเลิก', text: 'ยกเลิก' } }] },
  };
}

export function askWaterMinutes(window, choices) {
  const scope = window ? `ช่วง ${hhmm(window.start)}-${hhmm(window.end)}` : 'ทั้งวัน (เวลาอื่นทั้งหมด)';
  const labels = choices.map(durationText);
  const pick = timePicker('เลือกระยะเวลา', 'water:dur', '00:10', { min: '00:01', max: '03:00' });
  const rows = [{ type: 'button', style: 'primary', height: 'sm', color: BRAND, action: pick }];
  for (let i = 0; i < labels.length; i += 3) {
    rows.push({ type: 'box', layout: 'horizontal', spacing: 'sm', contents: labels.slice(i, i + 3).map((l) => button(l, 'secondary')) });
  }
  rows.push(button('ยกเลิก', 'link'));
  const b = bubble({
    header: header('ตั้งเวลาแจ้งเตือน', 'ไหลเกินกี่นาทีจึงเตือน'),
    body: [
      { type: 'text', text: scope, size: 'md', weight: 'bold', color: INK, wrap: true },
      { type: 'text', text: 'กด "เลือกระยะเวลา" แล้วหมุนเลือก ชั่วโมง:นาที เช่น 00:30 คือ 30 นาที, 01:15 คือ 1 ชั่วโมง 15 นาที', size: 'sm', color: INK, wrap: true },
      { type: 'text', text: 'หรือกดปุ่มลัด หรือพิมพ์เอง เช่น 7, 1.5, 90 วินาที (30 วินาที ถึง 3 ชั่วโมง)', size: 'sm', color: MUTED, wrap: true },
    ],
    footer: rows,
  });
  return {
    ...flex(`${scope} น้ำไหลเกินกี่นาทีจึงเตือน`, b),
    quickReply: { items: [{ type: 'action', action: pick }, ...quickReply([...labels, 'ยกเลิก']).items] },
  };
}
