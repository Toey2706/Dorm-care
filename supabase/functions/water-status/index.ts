import { jsonHandler } from '../_shared/http.js';
import { waterStatus } from '../_shared/water.js';
import { thingsboard } from '../_shared/thingsboard.js';
import { logger, rpcOf, userClient } from '../_shared/deno.ts';

const tb = thingsboard({ publicId: Deno.env.get('TB_PUBLIC_ID') ?? '495be850-e42c-11f1-b8a1-9db681a717b8' });

Deno.serve(
  jsonHandler(async (_body: unknown, req: Request) => {
    const db = userClient(req.headers.get('Authorization') ?? '');
    const isAdmin = await rpcOf(db)('is_admin');
    if (!isAdmin) throw Object.assign(new Error('ไม่มีสิทธิ์ดูข้อมูลอุปกรณ์วัดน้ำ'), { status: 403, code: 'permission-denied' });
    const devices = await waterStatus({
      devices: async () => {
        const { data, error } = await db.from('water_devices').select('id, room_no, label, tb_device_id').eq('active', true).order('room_no');
        if (error) throw error;
        return data ?? [];
      },
      telemetry: tb.telemetry,
      sum: tb.sum,
      logger,
    });
    return { devices };
  })
);
