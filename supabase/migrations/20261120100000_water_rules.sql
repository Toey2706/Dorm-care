create table public.water_alert_rules (
  id bigint generated always as identity primary key,
  room_no text not null references public.rooms (room_no),
  start_min smallint not null check (start_min between 0 and 1439),
  end_min smallint not null check (end_min between 0 and 1439),
  minutes smallint not null check (minutes between 5 and 180 and minutes % 5 = 0),
  created_by text,
  created_at timestamptz not null default now(),
  check (start_min <> end_min)
);
create index water_alert_rules_room_idx on public.water_alert_rules (room_no);

alter table public.water_alert_rules enable row level security;
create policy water_alert_rules_read on public.water_alert_rules for select to authenticated using (public.is_admin());
grant select on public.water_alert_rules to authenticated;
grant all on public.water_alert_rules to service_role;

create or replace function public.water_threshold(p_room_no text, p_at timestamptz) returns int
language sql stable security definer set search_path = public as $$
  with m as (
    select (extract(hour from p_at at time zone 'Asia/Bangkok') * 60
          + extract(minute from p_at at time zone 'Asia/Bangkok'))::int as v
  )
  select coalesce(max(r.minutes), 10)::int
    from public.water_alert_rules r, m
   where r.room_no = upper(p_room_no)
     and case when r.start_min < r.end_min then m.v >= r.start_min and m.v < r.end_min
              else m.v >= r.start_min or m.v < r.end_min end
$$;

create or replace function public.line_water_rules(p_user_id text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'room_no', b.room_no,
    'has_device', exists (select 1 from public.water_devices d where d.room_no = b.room_no and d.active),
    'rules', coalesce((select jsonb_agg(jsonb_build_object('start_min', r.start_min, 'end_min', r.end_min, 'minutes', r.minutes) order by r.start_min)
                         from public.water_alert_rules r where r.room_no = b.room_no), '[]'::jsonb))
    from public.line_bindings b
   where b.line_user_id = p_user_id and b.status = 'ACTIVE'
$$;

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
     or p_minutes not between 5 and 180 or p_minutes % 5 <> 0 then
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

create or replace function public.line_clear_water_rules(p_user_id text) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_room text;
  n int;
begin
  select room_no into v_room from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if v_room is null then return 0; end if;
  delete from public.water_alert_rules where room_no = v_room;
  get diagnostics n = row_count;
  return n;
end
$$;

revoke all on function public.water_threshold(text, timestamptz) from public, anon, authenticated;
revoke all on function public.line_water_rules(text) from public, anon, authenticated;
revoke all on function public.line_add_water_rule(text, int, int, int) from public, anon, authenticated;
revoke all on function public.line_clear_water_rules(text) from public, anon, authenticated;
grant execute on function public.water_threshold(text, timestamptz) to service_role;
grant execute on function public.line_water_rules(text) to service_role;
grant execute on function public.line_add_water_rule(text, int, int, int) to service_role;
grant execute on function public.line_clear_water_rules(text) to service_role;
