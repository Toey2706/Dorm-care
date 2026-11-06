// ส่วนที่ผูกกับ Deno และ Supabase จริง แยกไว้ไฟล์นี้ไฟล์เดียว ที่เหลือใน _shared เป็น JS ธรรมดาที่ทดสอบด้วย Node ได้
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { SMTPClient } from 'https://deno.land/x/denomailer@1.6.0/mod.ts';
import { jwtClaims } from './auth.js';

const HTTP_BY_HINT: Record<string, number> = {
  unauthenticated: 401,
  'permission-denied': 403,
  'not-found': 404,
  'failed-precondition': 409,
  'invalid-argument': 400,
  'resource-exhausted': 429,
};

export function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing secret ${name}`);
  return v;
}

export function serviceClient(): SupabaseClient {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
}

/** client ที่ใช้ JWT ของผู้เรียก ฐานข้อมูลจึงตรวจสิทธิ์และ session ของคนนั้นเอง */
export function userClient(authorization: string): SupabaseClient {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    auth: { persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
}

/** เรียกฟังก์ชันในฐานข้อมูล ถ้าฐานข้อมูลปฏิเสธด้วยรหัส (hint) จะได้ error ที่มี status และข้อความไทยพร้อมส่งให้แอป */
export function rpcOf(client: SupabaseClient) {
  return async (fn: string, args: Record<string, unknown> = {}) => {
    const { data, error } = await client.rpc(fn, args);
    if (error) {
      const err = new Error(error.message) as Error & { status?: number; code?: string };
      if (error.hint && HTTP_BY_HINT[error.hint]) {
        err.status = HTTP_BY_HINT[error.hint];
        err.code = error.hint;
      }
      throw err;
    }
    return data;
  };
}

/**
 * ส่งอีเมลผ่าน Gmail ของทีมด้วย App Password
 * ใช้พอร์ต 465 (TLS ตั้งแต่ต้น) เพราะ Edge Functions ปิดพอร์ต 25 และ 587
 */
export async function sendMail(to: string, mail: { subject: string; text: string }) {
  const user = env('GMAIL_USER');
  const client = new SMTPClient({
    connection: { hostname: 'smtp.gmail.com', port: 465, tls: true, auth: { username: user, password: env('GMAIL_APP_PASSWORD') } },
  });
  try {
    await client.send({ from: `ระบบแจ้งซ่อมหอพัก <${user}>`, to, subject: mail.subject, content: mail.text });
  } finally {
    await client.close();
  }
}

/**
 * คืน sub และ session_id ของผู้เรียก หลังให้ Supabase Auth ยืนยันว่าโทเคนยังใช้ได้ (ลายเซ็นถูกและ session ยังไม่ถูกยกเลิก)
 * โทเคนปลอมหรือหมดอายุได้ {} กลับไป
 */
export async function verifiedClaims(authorization: string | null) {
  const token = String(authorization ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return {};
  const { data, error } = await serviceClient().auth.getUser(token);
  if (error || !data.user) return {};
  const claims = jwtClaims(`Bearer ${token}`);
  return claims.userId === data.user.id ? claims : {};
}

export const logger = {
  warn: (msg: string, data?: unknown) => console.warn(msg, JSON.stringify(data ?? {})),
  error: (msg: string, data?: unknown) => console.error(msg, JSON.stringify(data ?? {})),
};
