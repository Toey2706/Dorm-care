alter table public.water_alert_rules drop constraint if exists water_alert_rules_minutes_check;
alter table public.water_alert_rules add constraint water_alert_rules_minutes_check check (minutes between 1 and 180);
alter table public.water_devices drop constraint if exists water_devices_default_minutes_check;
alter table public.water_devices add constraint water_devices_default_minutes_check check (default_minutes between 1 and 180);

create or replace function public.line_add_water_rule(p_user_id text, p_start int, p_end int, p_minutes int) returns jsonb
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
     or p_minutes not between 1 and 180 then
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

create or replace function public.line_set_water_default(p_user_id text, p_minutes int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_room text;
begin
  select room_no into v_room from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if v_room is null then return jsonb_build_object('result', 'NO_BINDING'); end if;
  if p_minutes is null or p_minutes not between 1 and 180 then
    return jsonb_build_object('result', 'INVALID', 'room_no', v_room);
  end if;
  update public.water_devices set default_minutes = p_minutes where room_no = v_room and active;
  if not found then return jsonb_build_object('result', 'NO_DEVICE', 'room_no', v_room); end if;
  return jsonb_build_object('result', 'OK', 'room_no', v_room);
end
$$;

revoke all on function public.line_add_water_rule(text, int, int, int) from public, anon, authenticated;
grant execute on function public.line_add_water_rule(text, int, int, int) to service_role;
revoke all on function public.line_set_water_default(text, int) from public, anon, authenticated;
grant execute on function public.line_set_water_default(text, int) to service_role;
