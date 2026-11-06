// verify_jwt = false ผู้ใช้พิสูจน์ตัวตนด้วย OTP ที่ส่งไปทางอีเมลแทน
import { jsonHandler } from '../_shared/http.js';
import { confirmPasswordReset } from '../_shared/auth.js';
import { rpcOf, serviceClient } from '../_shared/deno.ts';

const db = serviceClient();
const rpc = rpcOf(db);

async function setPassword(userId: string, password: string) {
  const { error } = await db.auth.admin.updateUserById(userId, { password });
  if (error) throw Object.assign(new Error(error.message), { status: 400, code: 'password-rejected' });
}

Deno.serve(
  jsonHandler((body) =>
    confirmPasswordReset({ rpc, setPassword }, { email: body.email, code: body.code, newPassword: body.new_password })
  )
);
