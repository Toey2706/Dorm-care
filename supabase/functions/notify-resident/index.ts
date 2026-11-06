// เรียกด้วย JWT ของผู้ดูแล โทเคนถูกส่งต่อให้ฐานข้อมูล ซึ่งตรวจลายเซ็นและตรวจว่าเป็นผู้ดูแลที่ผ่าน OTP แล้ว
// โทเคนปลอมจึงทำอะไรไม่ได้ แม้ gateway จะไม่ได้ตรวจก่อน (ดู config.toml)
import { jsonHandler } from '../_shared/http.js';
import { createClient as lineClient } from '../_shared/line.js';
import { notifyResident } from '../_shared/notify.js';
import { env, logger, rpcOf, userClient } from '../_shared/deno.ts';
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

// อ่านรายชื่อรูปและสร้างลิงก์ด้วยสิทธิ์ของผู้ดูแลคนที่กด RLS และ storage policy จึงยังตรวจสิทธิ์เหมือนตอนเปิดดูในแอป
function photoUrlsOf(db: SupabaseClient) {
  return async (ticketId: string, seconds: number): Promise<string[]> => {
    const { data, error } = await db.from('tickets').select('repair_photo_paths').eq('id', ticketId).single();
    if (error) throw error;
    const paths: string[] = data?.repair_photo_paths ?? [];
    if (paths.length === 0) return [];
    const signed = await db.storage.from('repair-photos').createSignedUrls(paths, seconds);
    if (signed.error) throw signed.error;
    return signed.data.filter((s) => s.signedUrl && !s.error).map((s) => s.signedUrl);
  };
}

Deno.serve(
  jsonHandler((body, req: Request) => {
    const db = userClient(req.headers.get('Authorization') ?? '');
    return notifyResident(
      { rpc: rpcOf(db), client: lineClient(env('LINE_CHANNEL_ACCESS_TOKEN')), logger, photoUrls: photoUrlsOf(db) },
      { ticketId: body.ticket_id, requestId: body.request_id }
    );
  })
);
