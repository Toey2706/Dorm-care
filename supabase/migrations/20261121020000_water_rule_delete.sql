create or replace function public.line_water_rules(p_user_id text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'room_no', b.room_no,
    'has_device', exists (select 1 from public.water_devices d where d.room_no = b.room_no and d.active),
    'default_minutes', coalesce((select d.default_minutes from public.water_devices d where d.room_no = b.room_no and d.active limit 1), 10),
    'rules', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'start_min', r.start_min, 'end_min', r.end_min, 'minutes', r.minutes) order by r.start_min)
                         from public.water_alert_rules r where r.room_no = b.room_no), '[]'::jsonb))
    from public.line_bindings b
   where b.line_user_id = p_user_id and b.status = 'ACTIVE'
$$;

create or replace function public.line_delete_water_rule(p_user_id text, p_rule_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  delete from public.water_alert_rules r
   using public.line_bindings b
   where r.id = p_rule_id and b.line_user_id = p_user_id and b.status = 'ACTIVE' and r.room_no = b.room_no;
  get diagnostics n = row_count;
  return n;
end
$$;

revoke all on function public.line_water_rules(text) from public, anon, authenticated;
grant execute on function public.line_water_rules(text) to service_role;
revoke all on function public.line_delete_water_rule(text, bigint) from public, anon, authenticated;
grant execute on function public.line_delete_water_rule(text, bigint) to service_role;
