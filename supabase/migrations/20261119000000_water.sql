create table public.water_devices (
  id text primary key,
  room_no text not null unique references public.rooms (room_no),
  tb_device_id uuid not null unique,
  label text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.water_alerts (
  id bigint generated always as identity primary key,
  room_no text not null references public.rooms (room_no),
  minutes int not null default 0,
  flow_lpm numeric(8, 2) not null default 0,
  total_l numeric(12, 1) not null default 0,
  line_sent int not null default 0,
  created_at timestamptz not null default now(),
  acked_by uuid references public.staff (user_id),
  acked_name text,
  acked_at timestamptz
);
create index water_alerts_created_idx on public.water_alerts (created_at desc);

alter table public.water_devices enable row level security;
alter table public.water_alerts enable row level security;
create policy water_devices_read on public.water_devices for select to authenticated using (public.is_admin());
create policy water_alerts_read on public.water_alerts for select to authenticated using (public.is_admin());
grant select on public.water_devices, public.water_alerts to authenticated;
grant all on public.water_devices, public.water_alerts to service_role;

create or replace function public.ack_water_alert(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
begin
  update public.water_alerts
     set acked_by = actor.user_id, acked_name = actor.name, acked_at = now()
   where id = p_id and acked_at is null;
  if not found then
    if exists (select 1 from public.water_alerts where id = p_id) then
      perform public.fail('failed-precondition', 'แจ้งเตือนนี้มีผู้รับเรื่องแล้ว');
    end if;
    perform public.fail('not-found', 'ไม่พบแจ้งเตือนนี้');
  end if;
end
$$;

revoke all on function public.ack_water_alert(bigint) from public, anon, authenticated;
grant execute on function public.ack_water_alert(bigint) to authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.water_alerts;
  end if;
end
$$;

insert into public.water_devices (id, room_no, tb_device_id, label)
select 'WF-001', 'A1-01', '8c5a0c30-e40f-11f1-a048-89a8198d067e', 'บอร์ดวัดน้ำ ตัวที่ 1'
 where exists (select 1 from public.rooms where room_no = 'A1-01')
on conflict do nothing;
