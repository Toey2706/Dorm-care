alter table public.water_alerts add column result text check (result in ('NORMAL', 'LEAK'));

drop function if exists public.ack_water_alert(bigint);

create or replace function public.close_water_alert(p_id bigint, p_result text) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
begin
  if p_result is null or p_result not in ('NORMAL', 'LEAK') then
    perform public.fail('invalid-argument', 'กรุณาเลือกผลการตรวจสอบ');
  end if;
  update public.water_alerts
     set acked_by = actor.user_id, acked_name = actor.name, acked_at = now(), result = p_result
   where id = p_id and acked_at is null;
  if not found then
    if exists (select 1 from public.water_alerts where id = p_id) then
      perform public.fail('failed-precondition', 'แจ้งเตือนนี้ปิดเรื่องไปแล้ว');
    end if;
    perform public.fail('not-found', 'ไม่พบแจ้งเตือนนี้');
  end if;
end
$$;

revoke all on function public.close_water_alert(bigint, text) from public, anon, authenticated;
grant execute on function public.close_water_alert(bigint, text) to authenticated, service_role;
