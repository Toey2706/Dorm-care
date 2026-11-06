// verify_jwt = false เพราะคนลืมรหัสผ่านยังล็อกอินไม่ได้ การขอรหัสซ้ำถูกจำกัดในฐานข้อมูล
import { jsonHandler } from '../_shared/http.js';
import { requestPasswordReset } from '../_shared/auth.js';
import { logger, rpcOf, sendMail, serviceClient } from '../_shared/deno.ts';

const rpc = rpcOf(serviceClient());

Deno.serve(jsonHandler((body) => requestPasswordReset({ rpc, sendMail, logger }, body)));
