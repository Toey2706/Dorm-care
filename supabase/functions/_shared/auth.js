/**
 * OTP ทางอีเมลสำหรับพนักงาน (ล็อกอินทุกครั้ง และลืมรหัสผ่าน)
 *
 * ฐานข้อมูลเป็นผู้ออกรหัส นับครั้งที่ผิด และจำกัดการขอซ้ำ ไฟล์นี้แค่เรียกฟังก์ชันแล้วส่งอีเมล
 * deps.rpc ใช้สิทธิ์ service_role, deps.sendMail ส่งอีเมลจริง, deps.setPassword ใช้ Admin API ของ Supabase Auth
 */

export const MIN_PASSWORD = 8;

export class AuthError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

export function otpMail(purpose, { name, code, ttlMin }) {
  const what = purpose === 'LOGIN' ? 'เข้าสู่ระบบ' : 'ตั้งรหัสผ่านใหม่';
  return {
    subject: `รหัสยืนยันสำหรับ${what} ระบบแจ้งซ่อมหอพัก`,
    text:
      `สวัสดีคุณ${name}\n\n` +
      `รหัสยืนยันสำหรับ${what}คือ ${code}\n` +
      `รหัสนี้ใช้ได้ ${ttlMin} นาที และใช้ได้ครั้งเดียว\n\n` +
      'ถ้าคุณไม่ได้ขอรหัสนี้ ไม่ต้องทำอะไร และไม่ต้องบอกรหัสให้ใคร หากได้รับอีเมลนี้บ่อยผิดปกติ ให้แจ้งผู้ดูแลระบบ',
  };
}

/** ขอ OTP ตอนล็อกอิน (ผู้เรียกล็อกอินด้วยรหัสผ่านแล้ว แต่ session ยังไม่ผ่านการยืนยัน) */
export async function sendLoginOtp({ rpc, sendMail }, { userId, sessionId }) {
  if (!userId || !sessionId) throw new AuthError(401, 'unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
  const r = await rpc('svc_create_otp', { p_purpose: 'LOGIN', p_user_id: userId, p_session_id: sessionId });
  if (!r.ok) {
    if (r.error === 'COOLDOWN') {
      throw new AuthError(429, 'cooldown', `ขอรหัสใหม่ได้ในอีก ${r.retry_in} วินาที`, { retry_in: r.retry_in });
    }
    throw new AuthError(403, 'not-staff', 'บัญชีนี้ไม่ได้ลงทะเบียนเป็นผู้ดูแลหรือช่าง');
  }
  await sendMail(r.email, otpMail('LOGIN', { name: r.name, code: r.code, ttlMin: r.ttl_min }));
  return { ok: true, channel: 'EMAIL' };
}

/**
 * ลืมรหัสผ่าน ขั้นที่ 1: ส่งรหัสไปที่อีเมล
 * ตอบเหมือนกันทุกกรณี ไม่ให้ใช้หน้านี้ตรวจว่าอีเมลไหนมีบัญชี
 */
export async function requestPasswordReset({ rpc, sendMail, logger }, { email }) {
  const clean = String(email || '').trim().toLowerCase();
  if (!clean.includes('@')) throw new AuthError(400, 'invalid-email', 'รูปแบบอีเมลไม่ถูกต้อง');
  const r = await rpc('svc_create_otp', { p_purpose: 'RESET', p_email: clean });
  if (r.ok) {
    try {
      await sendMail(r.email, otpMail('RESET', { name: r.name, code: r.code, ttlMin: r.ttl_min }));
    } catch (err) {
      // อีเมลส่งไม่ออกต้องรู้ ไม่งั้นผู้ใช้จะรอรหัสที่ไม่มีวันมา
      logger.error('reset mail failed', { error: err.message });
      throw new AuthError(503, 'mail-failed', 'ส่งอีเมลไม่สำเร็จ กรุณาลองใหม่ภายหลัง');
    }
  }
  return { ok: true };
}

const RESET_ERRORS = {
  INVALID: 'รหัสไม่ถูกต้อง',
  EXPIRED: 'รหัสหมดอายุหรือถูกใช้ไปแล้ว กรุณาขอรหัสใหม่',
  TOO_MANY: 'ใส่รหัสผิดหลายครั้งเกินไป กรุณาขอรหัสใหม่',
};

/** ลืมรหัสผ่าน ขั้นที่ 2: ตรวจรหัสแล้วตั้งรหัสผ่านใหม่ จากนั้นออกจากระบบทุกเครื่อง */
export async function confirmPasswordReset({ rpc, setPassword }, { email, code, newPassword }) {
  const password = String(newPassword || '');
  // ตรวจรหัสผ่านก่อนใช้ OTP ไม่งั้นรหัสผ่านสั้นไปทำให้เสีย OTP ไปฟรี ๆ
  if (password.length < MIN_PASSWORD) {
    throw new AuthError(400, 'weak-password', `รหัสผ่านต้องยาวอย่างน้อย ${MIN_PASSWORD} ตัวอักษร`);
  }
  const r = await rpc('svc_verify_reset_otp', { p_email: String(email || ''), p_code: String(code || '') });
  if (!r.ok) throw new AuthError(400, r.error.toLowerCase(), RESET_ERRORS[r.error] || RESET_ERRORS.INVALID);
  await setPassword(r.user_id, password);
  await rpc('svc_after_password_reset', { p_user_id: r.user_id });
  return { ok: true };
}

/** อ่าน sub และ session_id จาก JWT ที่ gateway ของ Supabase ตรวจลายเซ็นแล้ว */
export function jwtClaims(authorization) {
  const token = String(authorization || '').replace(/^Bearer\s+/i, '');
  const part = token.split('.')[1];
  if (!part) return {};
  try {
    const json = atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '='));
    const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(json, (c) => c.charCodeAt(0))));
    return { userId: claims.sub, sessionId: claims.session_id, role: claims.role };
  } catch {
    return {};
  }
}
