// ต่อ fcm.js เข้ากับตาราง staff_devices ใช้ทั้งใน staff-notify และ line-webhook (ตอนมีแจ้งซ่อมใหม่)
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { createFcm, notifyStaff } from './fcm.js';
import { logger } from './deno.ts';

let fcm: ReturnType<typeof createFcm> | null | undefined;

function fcmClient() {
  if (fcm !== undefined) return fcm;
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  // ยังไม่ได้ตั้ง Firebase ระบบอื่นต้องทำงานต่อได้ตามปกติ แค่ไม่มีแจ้งเตือน
  fcm = raw ? createFcm(JSON.parse(raw)) : null;
  if (!fcm) logger.warn('FCM_SERVICE_ACCOUNT not set, staff push disabled');
  return fcm;
}

export function staffPush(db: SupabaseClient) {
  const deps = {
    fcm: fcmClient(),
    logger,
    devices: async (userIds: string[]) => {
      const { data, error } = await db.from('staff_devices').select('token').in('user_id', userIds);
      if (error) throw error;
      return (data ?? []).map((d: { token: string }) => d.token);
    },
    removeDevices: async (tokens: string[]) => {
      await db.from('staff_devices').delete().in('token', tokens);
    },
  };
  return {
    toUsers: (userIds: string[], message: { title: string; body: string; data?: Record<string, string> }) => notifyStaff(deps, userIds, message),
    async toAdmins(message: { title: string; body: string; data?: Record<string, string> }) {
      const { data, error } = await db.from('staff').select('user_id').eq('role', 'ADMIN').eq('active', true);
      if (error) throw error;
      return notifyStaff(deps, (data ?? []).map((s: { user_id: string }) => s.user_id), message);
    },
  };
}
