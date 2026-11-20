alter table public.water_devices add column default_minutes smallint not null default 10
  check (default_minutes between 5 and 180 and default_minutes % 5 = 0);

create or replace function public.water_threshold(p_room_no text, p_at timestamptz) returns int
language sql stable security definer set search_path = public as $$
  with m as (
    select (extract(hour from p_at at time zone 'Asia/Bangkok') * 60
          + extract(minute from p_at at time zone 'Asia/Bangkok'))::int as v
  )
  select coalesce(
           (select max(r.minutes) from public.water_alert_rules r, m
             where r.room_no = upper(p_room_no)
               and case when r.start_min < r.end_min then m.v >= r.start_min and m.v < r.end_min
                        else m.v >= r.start_min or m.v < r.end_min end),
           (select d.default_minutes from public.water_devices d where d.room_no = upper(p_room_no) and d.active limit 1),
           10)::int
$$;

create or replace function public.line_water_rules(p_user_id text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'room_no', b.room_no,
    'has_device', exists (select 1 from public.water_devices d where d.room_no = b.room_no and d.active),
    'default_minutes', coalesce((select d.default_minutes from public.water_devices d where d.room_no = b.room_no and d.active limit 1), 10),
    'rules', coalesce((select jsonb_agg(jsonb_build_object('start_min', r.start_min, 'end_min', r.end_min, 'minutes', r.minutes) order by r.start_min)
                         from public.water_alert_rules r where r.room_no = b.room_no), '[]'::jsonb))
    from public.line_bindings b
   where b.line_user_id = p_user_id and b.status = 'ACTIVE'
$$;

create or replace function public.line_set_water_default(p_user_id text, p_minutes int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_room text;
begin
  select room_no into v_room from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if v_room is null then return jsonb_build_object('result', 'NO_BINDING'); end if;
  if p_minutes is null or p_minutes not between 5 and 180 or p_minutes % 5 <> 0 then
    return jsonb_build_object('result', 'INVALID', 'room_no', v_room);
  end if;
  update public.water_devices set default_minutes = p_minutes where room_no = v_room and active;
  if not found then return jsonb_build_object('result', 'NO_DEVICE', 'room_no', v_room); end if;
  return jsonb_build_object('result', 'OK', 'room_no', v_room);
end
$$;

revoke all on function public.line_set_water_default(text, int) from public, anon, authenticated;
grant execute on function public.line_set_water_default(text, int) to service_role;
revoke all on function public.water_threshold(text, timestamptz) from public, anon, authenticated;
revoke all on function public.line_water_rules(text) from public, anon, authenticated;
grant execute on function public.water_threshold(text, timestamptz) to service_role;
grant execute on function public.line_water_rules(text) to service_role;
