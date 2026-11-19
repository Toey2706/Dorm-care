import { waterAlert } from './messages.js';
import { sha256Hex } from './line.js';

const fail = (status, code, message) => Object.assign(new Error(message), { status, code });

export async function keyMatches(given, expected) {
  if (!given || !expected) return false;
  const [a, b] = await Promise.all([sha256Hex(given), sha256Hex(expected)]);
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const num = (v, digits) => {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) throw fail(400, 'invalid-argument', 'ค่าตัวเลขไม่ถูกต้อง');
  return Number(n.toFixed(digits));
};

export async function handleWaterAlert({ roomExists, residents, push, staff, logger, now = () => new Date() }, body) {
  const roomNo = String(body.room ?? '').trim().toUpperCase();
  if (!roomNo) throw fail(400, 'invalid-argument', 'ไม่มีเลขห้อง');
  if (!(await roomExists(roomNo))) throw fail(404, 'not-found', 'ไม่พบห้องนี้');

  const minutes = num(body.minutes ?? 0, 0);
  const flowLpm = num(body.flow_lpm ?? 0, 2);
  const totalL = num(body.total_l ?? 0, 1);
  const timeText = now().toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'short' });

  const message = waterAlert({ roomNo, minutes, flowLpm, totalL, timeText });
  const userIds = await residents(roomNo);
  let line = 0;
  for (const id of userIds) {
    try {
      await push(id, [message]);
      line += 1;
    } catch (err) {
      logger.error('water alert LINE push failed', { roomNo, status: err.status });
    }
  }

  let staffResult = { sent: 0 };
  try {
    staffResult = await staff({
      title: `น้ำไหลต่อเนื่องผิดปกติ ห้อง ${roomNo}`,
      body: `ไหลต่อเนื่อง ${minutes} นาที อัตราไหล ${flowLpm} L/min`,
      data: { kind: 'water', room: roomNo },
    });
  } catch (err) {
    logger.error('water alert staff push failed', { roomNo, message: err.message });
  }

  return { room: roomNo, line, residents: userIds.length, staff: staffResult };
}
