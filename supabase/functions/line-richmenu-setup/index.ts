// ผู้ดูแลเรียกครั้งเดียวหลังเปลี่ยนรูปเมนู หรือเมื่อต้องการให้เมนูของทุกคนตรงกับสถานะผูกห้องอีกครั้ง
// ตรวจสิทธิ์ด้วย is_admin() ในฐานข้อมูล ซึ่งนับเฉพาะผู้ดูแลที่ยืนยัน OTP ใน session นี้แล้ว
// (require_staff ไม่ได้เปิดให้ role authenticated เรียกตรง)
import { jsonHandler } from '../_shared/http.js';
import { richMenuApi, setupRichMenus } from '../_shared/richmenu.js';
import { env, rpcOf, serviceClient, userClient } from '../_shared/deno.ts';

// รูปเมนูอยู่ใน repo เดียวกับโค้ด ตัวแก้โค้ดบนหน้า Supabase เก็บไฟล์รูปไม่ได้ จึงโหลดจาก GitHub
const IMAGE_BASE = 'https://raw.githubusercontent.com/Toey2706/Dorm-care/main/supabase/functions/line-richmenu-setup/assets/';

Deno.serve(
  jsonHandler(async (_body: unknown, req: Request) => {
    const isAdmin = await rpcOf(userClient(req.headers.get('Authorization') ?? ''))('is_admin');
    if (isAdmin !== true) throw Object.assign(new Error('เฉพาะผู้ดูแลที่ยืนยันตัวตนแล้ว'), { status: 403, code: 'permission-denied' });

    const db = serviceClient();
    const { data, error } = await db.from('line_bindings').select('line_user_id, status');
    if (error) throw error;
    const active = [...new Set(data.filter((b) => b.status === 'ACTIVE').map((b) => b.line_user_id))];
    const revoked = [...new Set(data.filter((b) => b.status !== 'ACTIVE').map((b) => b.line_user_id))];

    return setupRichMenus({
      api: richMenuApi(env('LINE_CHANNEL_ACCESS_TOKEN')),
      loadImage: async (name: string) => {
        const res = await fetch(IMAGE_BASE + name);
        if (!res.ok) throw new Error(`load image ${name}: ${res.status}`);
        return { bytes: new Uint8Array(await res.arrayBuffer()), type: 'image/png' };
      },
      activeUserIds: active,
      revokedUserIds: revoked,
    });
  })
);
