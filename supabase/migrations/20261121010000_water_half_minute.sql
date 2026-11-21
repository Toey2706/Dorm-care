alter table public.water_alert_rules drop constraint if exists water_alert_rules_minutes_check;
alter table public.water_alert_rules alter column minutes type numeric(4,1);
alter table public.water_alert_rules add constraint water_alert_rules_minutes_check
  check (minutes between 0.5 and 180 and minutes * 2 = trunc(minutes * 2));

alter table public.water_devices drop constraint if exists water_devices_default_minutes_check;
alter table public.water_devices alter column default_minutes type numeric(4,1);
alter table public.water_devices add constraint water_devices_default_minutes_check
  check (default_minutes between 0.5 and 180 and default_minutes * 2 = trunc(default_minutes * 2));

alter table public.water_alerts alter column minutes type numeric(5,1);

drop function if exists public.water_threshold(text, timestamptz);
create function public.water_threshold(p_room_no text, p_at timestamptz) returns numeric
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
           10)
$$;

drop function if exists public.line_add_water_rule(text, int, int, int);
create function public.line_add_water_rule(p_user_id text, p_start int, p_end int, p_minutes numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_room text;
begin
  select room_no into v_room from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if v_room is null then return jsonb_build_object('result', 'NO_BINDING'); end if;
  if not exists (select 1 from public.water_devices where room_no = v_room and active) then
    return jsonb_build_object('result', 'NO_DEVICE', 'room_no', v_room);
  end if;
  if p_start is null or p_end is null or p_minutes is null
     or p_start not between 0 and 1439 or p_end not between 0 and 1439 or p_start = p_end
     or p_minutes not between 0.5 and 180 or p_minutes * 2 <> trunc(p_minutes * 2) then
    return jsonb_build_object('result', 'INVALID', 'room_no', v_room);
  end if;
  if (select count(*) from public.water_alert_rules where room_no = v_room) >= 5 then
    return jsonb_build_object('result', 'LIMIT', 'room_no', v_room);
  end if;
  insert into public.water_alert_rules (room_no, start_min, end_min, minutes, created_by)
  values (v_room, p_start, p_end, p_minutes, p_user_id);
  return jsonb_build_object('result', 'OK', 'room_no', v_room);
end
$$;

drop function if exists public.line_set_water_default(text, int);
create function public.line_set_water_default(p_user_id text, p_minutes numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_room text;
begin
  select room_no into v_room from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if v_room is null then return jsonb_build_object('result', 'NO_BINDING'); end if;
  if p_minutes is null or p_minutes not between 0.5 and 180 or p_minutes * 2 <> trunc(p_minutes * 2) then
    return jsonb_build_object('result', 'INVALID', 'room_no', v_room);
  end if;
  update public.water_devices set default_minutes = p_minutes where room_no = v_room and active;
  if not found then return jsonb_build_object('result', 'NO_DEVICE', 'room_no', v_room); end if;
  return jsonb_build_object('result', 'OK', 'room_no', v_room);
end
$$;

revoke all on function public.water_threshold(text, timestamptz) from public, anon, authenticated;
grant execute on function public.water_threshold(text, timestamptz) to service_role;
revoke all on function public.line_add_water_rule(text, int, int, numeric) from public, anon, authenticated;
grant execute on function public.line_add_water_rule(text, int, int, numeric) to service_role;
revoke all on function public.line_set_water_default(text, numeric) from public, anon, authenticated;
grant execute on function public.line_set_water_default(text, numeric) to service_role;
