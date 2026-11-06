// เรียกด้วย JWT ของผู้ดูแล โทเคนถูกส่งต่อให้ฐานข้อมูล ซึ่งตรวจลายเซ็นและตรวจว่าเป็นผู้ดูแลที่ผ่าน OTP แล้ว
// โทเคนปลอมจึงทำอะไรไม่ได้ แม้ gateway จะไม่ได้ตรวจก่อน (ดู config.toml)
import { jsonHandler } from '../_shared/http.js';
import { createClient as lineClient } from '../_shared/line.js';
import { notifyResident } from '../_shared/notify.js';
import { env, logger, rpcOf, userClient } from '../_shared/deno.ts';

Deno.serve(
  jsonHandler((body, req: Request) =>
    notifyResident(
      { rpc: rpcOf(userClient(req.headers.get('Authorization') ?? '')), client: lineClient(env('LINE_CHANNEL_ACCESS_TOKEN')), logger },
      { ticketId: body.ticket_id, requestId: body.request_id }
    )
  )
);
