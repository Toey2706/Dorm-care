-- รหัสเครื่อง (FCM token) ของแอป Android ไว้ส่งแจ้งเตือนงานให้พนักงาน
-- คนหนึ่งมีได้หลายเครื่อง รหัสเดียวเป็นของคนเดียว (ล็อกอินคนใหม่บนเครื่องเดิม รหัสย้ายไปเป็นของคนใหม่)
create table public.staff_devices (
  token text primary key,
  user_id uuid not null references public.staff (user_id) on delete cascade,
  platform text not null default 'android' check (platform in ('android')),
  updated_at timestamptz not null default now()
);
create index staff_devices_user_idx on public.staff_devices (user_id);

-- ไม่มี policy: แอปเขียนผ่านฟังก์ชันด้านล่าง ฟังก์ชันส่งแจ้งเตือนอ่านด้วย service role
alter table public.staff_devices enable row level security;

create or replace function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff();
begin
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    perform public.fail('invalid-argument', 'รหัสเครื่องไม่ถูกต้อง');
  end if;
  insert into public.staff_devices (token, user_id, updated_at)
  values (p_token, actor.user_id, now())
  on conflict (token) do update set user_id = excluded.user_id, updated_at = now();
end
$$;

-- เรียกก่อนออกจากระบบ เครื่องที่ออกจากระบบแล้วจะไม่ได้แจ้งเตือนงานของคนเดิมอีก
create or replace function public.unregister_device(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.staff_devices where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_device(text) from public, anon, authenticated;
revoke all on function public.unregister_device(text) from public, anon, authenticated;
grant execute on function public.register_device(text) to authenticated, service_role;
grant execute on function public.unregister_device(text) to authenticated, service_role;
