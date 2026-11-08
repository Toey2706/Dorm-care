// ผู้ดูแลเรียกครั้งเดียวหลังเปลี่ยนรูปเมนู หรือเมื่อต้องการให้เมนูของทุกคนตรงกับสถานะผูกห้องอีกครั้ง
// ตรวจสิทธิ์ผู้ดูแลด้วย require_staff ในฐานข้อมูล แบบเดียวกับฟังก์ชันอื่นของแอป
import { jsonHandler } from '../_shared/http.js';
import { richMenuApi, setupRichMenus } from '../_shared/richmenu.js';
import { env, rpcOf, serviceClient, userClient } from '../_shared/deno.ts';

// รูปเมนูอยู่ใน repo เดียวกับโค้ด ตัวแก้โค้ดบนหน้า Supabase เก็บไฟล์รูปไม่ได้ จึงโหลดจาก GitHub
const IMAGE_BASE = 'https://raw.githubusercontent.com/Toey2706/Dorm-care/main/supabase/functions/line-richmenu-setup/assets/';

Deno.serve(
  jsonHandler(async (_body: unknown, req: Request) => {
    await rpcOf(userClient(req.headers.get('Authorization') ?? ''))('require_staff', { p_role: 'ADMIN' });

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
