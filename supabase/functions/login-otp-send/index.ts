// ผู้เรียกต้องล็อกอินด้วยรหัสผ่านแล้ว ใช้ sub และ session_id ในโทเคนผูก OTP กับ session นั้น
// gateway ไม่ได้ตรวจโทเคน (ดู config.toml) จึงตรวจกับ Supabase Auth ก่อนเชื่อค่าในโทเคน
import { jsonHandler } from '../_shared/http.js';
import { sendLoginOtp } from '../_shared/auth.js';
import { rpcOf, sendMail, serviceClient, verifiedClaims } from '../_shared/deno.ts';

const rpc = rpcOf(serviceClient());

Deno.serve(jsonHandler(async (_body, req: Request) => sendLoginOtp({ rpc, sendMail }, await verifiedClaims(req.headers.get('Authorization')))));
