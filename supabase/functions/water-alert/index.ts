import { json, jsonHandler } from '../_shared/http.js';
import { createClient as lineClient } from '../_shared/line.js';
import { handleWaterAlert, keyMatches } from '../_shared/water.js';
import { env, logger, serviceClient } from '../_shared/deno.ts';

const handler = jsonHandler((body: Record<string, unknown>) => {
  const db = serviceClient();
  const line = lineClient(env('LINE_CHANNEL_ACCESS_TOKEN'));
  return handleWaterAlert(
    {
      roomExists: async (roomNo: string) => {
        const { data, error } = await db.from('water_devices').select('room_no').eq('room_no', roomNo).eq('active', true).maybeSingle();
        if (error) throw error;
        return Boolean(data);
      },
      residents: async (roomNo: string) => {
        const { data, error } = await db.from('line_bindings').select('line_user_id').eq('room_no', roomNo).eq('status', 'ACTIVE');
        if (error) throw error;
        return (data ?? []).map((r: { line_user_id: string }) => r.line_user_id);
      },
      push: (to: string, messages: unknown[]) => line.push(to, messages),
      threshold: async (roomNo: string, startedAt: Date) => {
        const { data, error } = await db.rpc('water_threshold', { p_room_no: roomNo, p_at: startedAt.toISOString() });
        if (error) throw error;
        return Number(data);
      },
      record: async (row: Record<string, unknown>) => {
        const { error } = await db.from('water_alerts').insert(row);
        if (error) throw error;
      },
      logger,
    },
    body
  );
});

Deno.serve(async (req: Request) => {
  if (req.method === 'POST' && !(await keyMatches(req.headers.get('x-device-key') ?? '', Deno.env.get('WATER_DEVICE_KEY') ?? ''))) {
    return json(401, { error: 'unauthenticated', message: 'อุปกรณ์ไม่ได้รับอนุญาต' });
  }
  return handler(req);
});
