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

export const PING_MINUTES = 5;

export async function handleWaterAlert({ roomExists, residents, push, staff, record, threshold, logger, now = () => new Date() }, body) {
  const roomNo = String(body.room ?? '').trim().toUpperCase();
  if (!roomNo) throw fail(400, 'invalid-argument', 'ไม่มีเลขห้อง');
  if (!(await roomExists(roomNo))) throw fail(404, 'not-found', 'ไม่พบห้องนี้');

  const minutes = num(body.minutes ?? 0, 0);
  const flowLpm = num(body.flow_lpm ?? 0, 2);
  const totalL = num(body.total_l ?? 0, 1);
  const test = body.test === true;
  const at = now();

  let limit = null;
  if (threshold && !test) {
    limit = await threshold(roomNo, new Date(at.getTime() - minutes * 60_000));
    if (!(minutes >= limit && minutes - PING_MINUTES < limit)) {
      return { room: roomNo, skipped: true, threshold: limit };
    }
  }

  const timeText = at.toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'short' });
  const message = waterAlert({ roomNo, minutes, flowLpm, totalL, timeText, test, limit });
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
  if (staff) {
    try {
      staffResult = await staff({
        title: `น้ำไหลต่อเนื่องผิดปกติ ห้อง ${roomNo}`,
        body: `ไหลต่อเนื่อง ${minutes} นาที อัตราไหล ${flowLpm} L/min`,
        data: { kind: 'water', room: roomNo },
      });
    } catch (err) {
      logger.error('water alert staff push failed', { roomNo, message: err.message });
    }
  }

  if (record) {
    try {
      await record({ room_no: roomNo, minutes, flow_lpm: flowLpm, total_l: totalL, line_sent: line });
    } catch (err) {
      logger.error('water alert record failed', { roomNo, message: err.message });
    }
  }

  return { room: roomNo, line, residents: userIds.length, staff: staffResult, threshold: limit };
}

const ONLINE_MS = 60_000;
const KEYS = ['flow_lpm', 'total_l', 'flowing', 'flow_seconds', 'leak', 'rssi'];

const latest = (series, key) => (Array.isArray(series?.[key]) && series[key][0]) || null;

export function summarizeTelemetry(series, nowMs) {
  const points = KEYS.map((k) => latest(series, k)).filter(Boolean);
  if (points.length === 0) return { online: false, last_seen: null };
  const ts = Math.max(...points.map((p) => Number(p.ts) || 0));
  const val = (k) => latest(series, k)?.value;
  const n = (k) => {
    const v = Number(val(k));
    return Number.isFinite(v) ? v : null;
  };
  const b = (k) => String(val(k)) === 'true';
  const flowing = b('flowing');
  const leak = b('leak');
  return {
    online: nowMs - ts <= ONLINE_MS,
    last_seen: new Date(ts).toISOString(),
    flow_lpm: n('flow_lpm'),
    total_l: n('total_l'),
    flowing,
    flow_seconds: n('flow_seconds'),
    leak,
    rssi: n('rssi'),
    state: leak ? 'LEAK' : flowing ? 'FLOWING' : 'IDLE',
  };
}

const BKK_MS = 7 * 3600_000;
const DAY_MS = 86_400_000;

export function usageWindows(nowMs) {
  const today = Math.floor((nowMs + BKK_MS) / DAY_MS) * DAY_MS - BKK_MS;
  return { today, week: today - 6 * DAY_MS, month: today - 29 * DAY_MS, end: nowMs };
}

export async function waterUsage({ sum, deviceId, nowMs }) {
  const w = usageWindows(nowMs);
  const [today_l, week_l, month_l] = await Promise.all([w.today, w.week, w.month].map((start) => sum(deviceId, 'used_l', start, w.end)));
  return { today_l, week_l, month_l, at: new Date(nowMs).toISOString() };
}

export async function waterStatus({ devices, telemetry, sum = null, logger, now = () => new Date() }) {
  const list = await devices();
  const nowMs = now().getTime();
  return Promise.all(
    list.map(async (d) => {
      const base = { id: d.id, room_no: d.room_no, label: d.label ?? '' };
      try {
        const status = { ...base, ...summarizeTelemetry(await telemetry(d.tb_device_id, KEYS), nowMs) };
        if (sum) {
          status.usage = await waterUsage({ sum, deviceId: d.tb_device_id, nowMs }).catch((err) => {
            logger.warn('water usage failed', { id: d.id, message: err.message });
            return null;
          });
        }
        return status;
      } catch (err) {
        logger.error('water telemetry failed', { id: d.id, message: err.message });
        return { ...base, online: false, last_seen: null, error: 'อ่านค่าจากอุปกรณ์ไม่ได้' };
      }
    })
  );
}
