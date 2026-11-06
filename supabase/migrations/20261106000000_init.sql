-- ระบบแจ้งซ่อมหอพัก: ฐานข้อมูลบน Supabase
--
-- หลักการ:
-- * แอปอ่านข้อมูลตาม RLS แต่เขียนเองไม่ได้ ทุกการเปลี่ยนข้อมูลผ่านฟังก์ชัน (RPC) ที่ตรวจสิทธิ์และสถานะในทรานแซกชันเดียว
-- * พนักงานต้องผ่าน OTP (หรือใช้เครื่องที่จำไว้ 30 วัน) ก่อน session นั้นจะอ่านหรือแก้ข้อมูลได้
--   ล็อกอินด้วยรหัสผ่านอย่างเดียวได้แค่ session ที่ยังไม่ยืนยัน
-- * ฟังก์ชันที่ขึ้นต้นด้วย svc_ และ line_ เรียกได้เฉพาะ service_role (Edge Functions) เท่านั้น
-- * นับวันและปี พ.ศ. ตามเวลาไทย

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- ตาราง
-- ---------------------------------------------------------------------------

create table public.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  name text not null,
  phone text,                                   -- เบอร์ติดต่อ ไม่ได้ใช้ยืนยันตัวตน
  role text not null check (role in ('ADMIN', 'TECHNICIAN')),
  active boolean not null default true,
  must_change_password boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.rooms (
  room_no text primary key,
  active boolean not null default true
);

create table public.settings (
  key text primary key,
  value text not null
);

create table public.invite_codes (
  code_hash text primary key,                   -- เก็บเฉพาะ SHA-256 ของรหัส
  room_no text not null references public.rooms (room_no),
  status text not null default 'UNUSED' check (status in ('UNUSED', 'USED')),
  created_by uuid references public.staff (user_id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_by text,
  used_at timestamptz
);

-- เก็บทุกครั้งที่ผูกห้อง (ย้ายห้องแล้วผูกใหม่ได้รายการใหม่ รายการเก่ายังอยู่เป็นประวัติ)
-- บัญชี LINE หนึ่งบัญชีมีรายการ ACTIVE ได้ทีละรายการเดียว
create table public.line_bindings (
  id bigint generated always as identity primary key,
  line_user_id text not null,
  room_no text not null references public.rooms (room_no),
  display_name text not null default '',
  status text not null check (status in ('ACTIVE', 'REVOKED')),
  bound_at timestamptz not null default now(),
  invite_code_hash text,
  revoked_by uuid references public.staff (user_id),
  revoked_at timestamptz
);
create unique index line_bindings_one_active on public.line_bindings (line_user_id) where status = 'ACTIVE';
create index line_bindings_room_idx on public.line_bindings (room_no) where status = 'ACTIVE';
create index line_bindings_user_idx on public.line_bindings (line_user_id, bound_at desc);

create table public.bind_attempts (
  line_user_id text not null,
  day date not null,
  failed int not null default 0,
  primary key (line_user_id, day)
);

create table public.line_sessions (
  line_user_id text primary key,
  state text not null,
  draft jsonb,
  version int not null default 0,              -- กันเหตุการณ์ที่มาพร้อมกันเขียนทับกัน
  updated_at timestamptz not null default now()
);

create table public.processed_events (
  event_id text primary key,
  processed_at timestamptz not null default now()
);

create table public.counters (
  name text primary key,
  value int not null
);

create table public.tickets (
  id text primary key,
  ticket_no text not null unique,
  room_no text not null references public.rooms (room_no),
  line_user_id text not null,
  binding_id bigint references public.line_bindings (id),  -- การผูกห้องที่ใช้ตอนแจ้ง
  reporter_name text not null default '',
  category text not null check (category in ('PLUMBING', 'ELECTRICAL', 'AIRCON', 'FURNITURE', 'OTHER')),
  description text not null check (char_length(description) between 1 and 1000),
  photo_paths text[] not null default '{}',
  status text not null default 'PENDING' check (status in ('PENDING', 'REPAIRING', 'COMPLETED')),
  assigned_to uuid references public.staff (user_id),
  assigned_to_name text,
  inspection_note text check (char_length(inspection_note) <= 1000),
  repair_result text check (char_length(repair_result) <= 1000),
  repair_photo_paths text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  notified_at timestamptz,
  -- คอลัมน์คำนวณให้แอปกรองแบบ realtime ได้ด้วยเงื่อนไขเดียว
  is_open boolean generated always as (status in ('PENDING', 'REPAIRING')) stored,
  awaiting_notify boolean generated always as (status = 'COMPLETED' and notified_at is null) stored
);
create index tickets_status_idx on public.tickets (status, created_at desc);
create index tickets_room_idx on public.tickets (room_no, created_at desc);
create index tickets_assigned_idx on public.tickets (assigned_to, status, created_at desc);
create index tickets_open_idx on public.tickets (is_open, created_at desc);
create index tickets_awaiting_idx on public.tickets (awaiting_notify, created_at desc);

create table public.ticket_history (
  id bigint generated always as identity primary key,
  ticket_id text not null references public.tickets (id) on delete cascade,
  action text not null,                         -- CREATE ASSIGN REASSIGN START COMPLETE NOTIFY_LINE
  from_status text,
  to_status text,
  actor_id uuid,
  actor_name text not null default '',
  actor_role text not null,                     -- RESIDENT ADMIN TECHNICIAN
  note text not null default '',
  at timestamptz not null default now()
);
create index ticket_history_ticket_idx on public.ticket_history (ticket_id, at);

create table public.notifications (
  request_id uuid primary key,
  ticket_id text not null references public.tickets (id),
  to_line_user_id text not null,
  status text not null check (status in ('SENDING', 'SENT', 'FAILED')),
  sent_by uuid not null,
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

-- ---- การยืนยันตัวตนพนักงาน ----

create table public.verified_sessions (          -- session ที่ผ่าน OTP หรือเครื่องที่จำไว้แล้ว
  session_id uuid primary key,
  user_id uuid not null references public.staff (user_id) on delete cascade,
  method text not null check (method in ('OTP_EMAIL', 'TRUSTED_DEVICE')),
  verified_at timestamptz not null default now()
);

create table public.trusted_devices (
  token_hash text primary key,
  user_id uuid not null references public.staff (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz
);

create table public.otp_codes (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.staff (user_id) on delete cascade,
  purpose text not null check (purpose in ('LOGIN', 'RESET')),
  session_id uuid,                              -- LOGIN ผูกกับ session ที่ขอรหัส
  code_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  attempts int not null default 0,
  consumed_at timestamptz
);
create index otp_codes_lookup_idx on public.otp_codes (user_id, purpose, created_at desc);

-- ---------------------------------------------------------------------------
-- ค่าคงที่และฟังก์ชันช่วย
-- ---------------------------------------------------------------------------

create or replace function public.cfg(p_key text) returns int
language sql immutable as $$
  select case p_key
    when 'CODE_TTL_DAYS' then 3          -- อายุรหัสผูกห้อง (ทีมกำหนด 3 พ.ย. 2569)
    when 'MAX_BIND_FAILED' then 5        -- ใส่รหัสผูกห้องผิดได้ต่อวัน
    when 'OTP_TTL_MIN' then 10
    when 'OTP_MAX_ATTEMPTS' then 5
    when 'OTP_RESEND_SEC' then 60
    when 'TRUST_DAYS' then 30
  end
$$;

create or replace function public.thai_now() returns timestamp
language sql stable as $$ select now() at time zone 'Asia/Bangkok' $$;

create or replace function public.sha256_hex(p text) returns text
language sql immutable as $$ select encode(extensions.digest(p, 'sha256'), 'hex') $$;

create or replace function public.random_digits(n int) returns text
language plpgsql volatile as $$
declare
  v text := '';
  b bytea := extensions.gen_random_bytes(n * 2);
  i int;
begin
  -- 2 ไบต์ต่อหลัก ลดความเอียงของการ mod 10 จนไม่มีนัยสำคัญ
  for i in 0 .. n - 1 loop
    v := v || ((get_byte(b, i * 2) * 256 + get_byte(b, i * 2 + 1)) % 10)::text;
  end loop;
  return v;
end
$$;

create or replace function public.current_session_id() returns uuid
language sql stable as $$
  select nullif(auth.jwt() ->> 'session_id', '')::uuid
$$;

-- พนักงานที่ใช้งานอยู่และ session นี้ผ่านการยืนยันแล้ว
create or replace function public.me() returns public.staff
language sql stable security definer set search_path = public as $$
  select s.* from public.staff s
  join public.verified_sessions v on v.user_id = s.user_id and v.session_id = public.current_session_id()
  where s.user_id = auth.uid() and s.active
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.me()).role = 'ADMIN', false)
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select (public.me()).user_id is not null
$$;

create or replace function public.fail(p_code text, p_message text) returns void
language plpgsql as $$
begin
  -- แอปอ่าน hint เป็นรหัสข้อผิดพลาด และแสดง message ภาษาไทยให้ผู้ใช้
  raise exception using message = p_message, hint = p_code, errcode = 'P0001';
end
$$;

create or replace function public.require_staff(p_role text default null) returns public.staff
language plpgsql stable security definer set search_path = public as $$
declare
  s public.staff := public.me();
begin
  if s.user_id is null then
    perform public.fail('unauthenticated', 'กรุณาเข้าสู่ระบบและยืนยันตัวตนก่อน');
  end if;
  if p_role is not null and s.role <> p_role then
    perform public.fail('permission-denied', 'ไม่มีสิทธิ์ทำรายการนี้');
  end if;
  return s;
end
$$;

create or replace function public.add_history(p_ticket_id text, p_action text, p_from text, p_to text, p_actor public.staff, p_note text)
returns void language sql security definer set search_path = public as $$
  insert into public.ticket_history (ticket_id, action, from_status, to_status, actor_id, actor_name, actor_role, note)
  values (p_ticket_id, p_action, p_from, p_to, p_actor.user_id, coalesce(p_actor.name, ''), p_actor.role, coalesce(p_note, ''));
$$;

-- ---------------------------------------------------------------------------
-- งานซ่อม (แอปผู้ดูแลและช่าง)
-- ---------------------------------------------------------------------------

create or replace function public.lock_ticket(p_ticket_id text) returns public.tickets
language plpgsql security definer set search_path = public as $$
declare
  t public.tickets;
begin
  select * into t from public.tickets where id = p_ticket_id for update;
  if not found then
    perform public.fail('not-found', 'ไม่พบใบแจ้งซ่อม');
  end if;
  return t;
end
$$;

/** ผู้ดูแลมอบหมาย (หรือเปลี่ยน) ช่าง ทำได้เฉพาะงานที่ยังไม่เริ่มซ่อม สถานะยังเป็น PENDING */
create or replace function public.assign_ticket(p_ticket_id text, p_technician_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
  t public.tickets := public.lock_ticket(p_ticket_id);
  tech public.staff;
begin
  if t.status <> 'PENDING' then
    perform public.fail('failed-precondition', 'มอบหมายได้เฉพาะงานที่รอดำเนินการ');
  end if;
  select * into tech from public.staff where user_id = p_technician_id and role = 'TECHNICIAN' and active;
  if not found then
    perform public.fail('invalid-argument', 'ต้องเลือกช่างที่ใช้งานอยู่');
  end if;
  update public.tickets
     set assigned_to = tech.user_id, assigned_to_name = tech.name, updated_at = now()
   where id = t.id;
  perform public.add_history(t.id, case when t.assigned_to is null then 'ASSIGN' else 'REASSIGN' end,
                             t.status, t.status, actor, 'มอบหมายให้ ' || tech.name);
end
$$;

create or replace function public.require_assigned(t public.tickets, actor public.staff) returns void
language plpgsql as $$
begin
  if t.assigned_to is distinct from actor.user_id then
    perform public.fail('permission-denied', 'งานนี้ไม่ได้มอบหมายให้คุณ');
  end if;
end
$$;

/** ช่างกดเริ่มซ่อม: PENDING -> REPAIRING */
create or replace function public.start_repair(p_ticket_id text) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('TECHNICIAN');
  t public.tickets := public.lock_ticket(p_ticket_id);
begin
  perform public.require_assigned(t, actor);
  if t.status <> 'PENDING' then
    perform public.fail('failed-precondition', 'เริ่มซ่อมได้เฉพาะงานที่รอดำเนินการ');
  end if;
  update public.tickets set status = 'REPAIRING', updated_at = now() where id = t.id;
  perform public.add_history(t.id, 'START', 'PENDING', 'REPAIRING', actor, '');
end
$$;

/**
 * ช่างบันทึกผล: REPAIRING -> COMPLETED ทันที (ทีมยืนยัน 3 พ.ย. 2569 ไม่มีขั้นอนุมัติ/ส่งกลับ)
 * ไม่ส่ง LINE เอง ผู้ดูแลเป็นผู้กดแจ้งผล
 */
create or replace function public.submit_result(p_ticket_id text, p_inspection text, p_result text, p_photo_paths text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('TECHNICIAN');
  t public.tickets := public.lock_ticket(p_ticket_id);
  inspection text := btrim(coalesce(p_inspection, ''));
  result text := btrim(coalesce(p_result, ''));
  photos text[] := coalesce(p_photo_paths, '{}');
  p text;
begin
  perform public.require_assigned(t, actor);
  if t.status <> 'REPAIRING' then
    perform public.fail('failed-precondition', 'บันทึกผลได้เฉพาะงานที่กำลังซ่อม');
  end if;
  if inspection = '' or result = '' then
    perform public.fail('invalid-argument', 'กรุณากรอกสิ่งที่ตรวจพบและผลการซ่อม');
  end if;
  if char_length(inspection) > 1000 or char_length(result) > 1000 then
    perform public.fail('invalid-argument', 'ข้อความยาวเกิน 1000 ตัวอักษร');
  end if;
  if coalesce(array_length(photos, 1), 0) > 3 then
    perform public.fail('invalid-argument', 'แนบรูปได้ไม่เกิน 3 รูป');
  end if;
  foreach p in array photos loop
    if p not like t.id || '/%' then
      perform public.fail('invalid-argument', 'ตำแหน่งไฟล์รูปไม่ถูกต้อง');
    end if;
  end loop;
  update public.tickets
     set status = 'COMPLETED', inspection_note = inspection, repair_result = result,
         repair_photo_paths = photos, completed_at = now(), updated_at = now()
   where id = t.id;
  perform public.add_history(t.id, 'COMPLETE', 'REPAIRING', 'COMPLETED', actor, 'ช่างบันทึกผลซ่อม');
end
$$;

/**
 * แจ้งผลทาง LINE ขั้นที่ 1: ตรวจสิทธิ์และจองบันทึกก่อนส่ง (Edge Function เรียกด้วย JWT ของผู้ดูแล)
 * คืน action = SEND (ให้ส่ง) หรือ DUPLICATE (คำขอนี้ส่งสำเร็จไปแล้ว)
 */
create or replace function public.begin_notify(p_ticket_id text, p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
  t public.tickets;
  n public.notifications;
begin
  select * into t from public.tickets where id = p_ticket_id;
  if not found then
    perform public.fail('not-found', 'ไม่พบใบแจ้งซ่อม');
  end if;
  if t.status <> 'COMPLETED' then
    perform public.fail('failed-precondition', 'แจ้งผลได้หลังช่างบันทึกผลซ่อมแล้วเท่านั้น');
  end if;
  insert into public.notifications (request_id, ticket_id, to_line_user_id, status, sent_by)
  values (p_request_id, t.id, t.line_user_id, 'SENDING', actor.user_id)
  on conflict (request_id) do nothing;
  select * into n from public.notifications where request_id = p_request_id;
  if n.ticket_id <> t.id then
    perform public.fail('invalid-argument', 'รหัสคำขอซ้ำกับรายการอื่น');
  end if;
  return jsonb_build_object(
    'action', case when n.status = 'SENT' then 'DUPLICATE' else 'SEND' end,
    'ticket', jsonb_build_object('id', t.id, 'ticket_no', t.ticket_no, 'room_no', t.room_no, 'category', t.category,
                                 'repair_result', t.repair_result, 'line_user_id', t.line_user_id));
end
$$;

/** แจ้งผลทาง LINE ขั้นที่ 2: บันทึกผลการส่ง ถ้าส่งสำเร็จ บันทึกเวลาแจ้งผลและประวัติ */
create or replace function public.finish_notify(p_request_id uuid, p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
  n public.notifications;
begin
  select * into n from public.notifications where request_id = p_request_id for update;
  if not found then
    perform public.fail('not-found', 'ไม่พบคำขอแจ้งผล');
  end if;
  if not p_ok then
    update public.notifications set status = 'FAILED', error = left(p_error, 500) where request_id = p_request_id and status <> 'SENT';
    return;
  end if;
  if n.status = 'SENT' then
    return;
  end if;
  update public.notifications set status = 'SENT', sent_at = now(), error = null where request_id = p_request_id;
  update public.tickets set notified_at = now(), updated_at = now() where id = n.ticket_id;
  perform public.add_history(n.ticket_id, 'NOTIFY_LINE', 'COMPLETED', 'COMPLETED', actor, 'ส่งข้อความแจ้งผลทาง LINE');
end
$$;

-- ---------------------------------------------------------------------------
-- ผูกห้อง (ฝั่งผู้ดูแล)
-- ---------------------------------------------------------------------------

/** ออกรหัส 6 หลัก ใช้ได้ครั้งเดียว หมดอายุใน 3 วัน คืนตัวรหัสครั้งเดียว ฐานข้อมูลเก็บเฉพาะ Hash */
create or replace function public.create_invite_code(p_room_no text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
  room text := upper(btrim(coalesce(p_room_no, '')));
  code text;
  expires timestamptz := now() + make_interval(days => public.cfg('CODE_TTL_DAYS'));
  attempt int;
begin
  if not exists (select 1 from public.rooms where room_no = room and active) then
    perform public.fail('not-found', 'ไม่พบห้อง ' || room);
  end if;
  for attempt in 1 .. 5 loop
    code := public.random_digits(6);
    insert into public.invite_codes (code_hash, room_no, created_by, expires_at)
    values (public.sha256_hex(code), room, actor.user_id, expires)
    on conflict (code_hash) do nothing;
    if found then
      return jsonb_build_object('code', code, 'room_no', room, 'expires_at', expires);
    end if;
  end loop;
  perform public.fail('resource-exhausted', 'ออกรหัสไม่สำเร็จ กรุณาลองใหม่');
  return null;
end
$$;

/** ยกเลิกการผูกห้อง เช่น ผู้พักย้ายออก สิทธิ์สิ้นสุดทันที */
create or replace function public.revoke_binding(p_line_user_id text) returns void
language plpgsql security definer set search_path = public as $$
declare
  actor public.staff := public.require_staff('ADMIN');
begin
  update public.line_bindings
     set status = 'REVOKED', revoked_at = now(), revoked_by = actor.user_id
   where line_user_id = p_line_user_id and status = 'ACTIVE';
  if not found then
    perform public.fail('failed-precondition', 'ไม่พบการผูกห้องที่ใช้งานอยู่');
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- การยืนยันตัวตนพนักงาน (session ที่ล็อกอินด้วยรหัสผ่านแล้ว แต่ยังไม่ยืนยัน)
-- ---------------------------------------------------------------------------

create or replace function public.mask_email(p text) returns text
language sql immutable as $$
  select case when position('@' in p) > 1
    then left(p, 1) || repeat('*', greatest(position('@' in p) - 2, 1)) || substr(p, position('@' in p))
    else p end
$$;

/** สถานะของ session ปัจจุบัน ใช้ตัดสินว่าแอปต้องไปหน้าไหน */
create or replace function public.auth_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.staff;
  verified boolean;
begin
  select * into s from public.staff where user_id = auth.uid();
  if not found or not s.active then
    return jsonb_build_object('registered', false);
  end if;
  verified := exists (select 1 from public.verified_sessions where session_id = public.current_session_id() and user_id = s.user_id);
  return jsonb_build_object(
    'registered', true, 'verified', verified, 'must_change_password', s.must_change_password,
    'role', s.role, 'name', s.name, 'email', s.email, 'phone', s.phone, 'email_masked', public.mask_email(s.email));
end
$$;

/** เครื่องที่เคยยืนยันภายใน 30 วัน: ส่งโทเคนของเครื่องมา ถ้าถูกต้อง session นี้ผ่านโดยไม่ต้องใช้ OTP */
create or replace function public.verify_trusted_device(p_device_token text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  sid uuid := public.current_session_id();
  d public.trusted_devices;
begin
  if auth.uid() is null or sid is null or coalesce(p_device_token, '') = '' then
    return false;
  end if;
  select * into d from public.trusted_devices
   where token_hash = public.sha256_hex(p_device_token) and user_id = auth.uid() and expires_at > now();
  if not found then
    return false;
  end if;
  if not exists (select 1 from public.staff where user_id = auth.uid() and active) then
    return false;
  end if;
  update public.trusted_devices set last_used_at = now() where token_hash = d.token_hash;
  insert into public.verified_sessions (session_id, user_id, method) values (sid, auth.uid(), 'TRUSTED_DEVICE')
  on conflict (session_id) do nothing;
  return true;
end
$$;

/**
 * ตรวจ OTP ตอนล็อกอิน ผ่านแล้ว session นี้ใช้งานได้ และออกโทเคนจำเครื่องอายุ 30 วัน (คืนครั้งเดียว)
 * ผลลัพธ์: ok, device_token หรือ error = INVALID | EXPIRED | TOO_MANY
 */
create or replace function public.verify_login_otp(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sid uuid := public.current_session_id();
  o public.otp_codes;
  token text;
begin
  if auth.uid() is null or sid is null then
    perform public.fail('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
  end if;
  select * into o from public.otp_codes
   where user_id = auth.uid() and purpose = 'LOGIN' and session_id = sid and consumed_at is null
   order by created_at desc limit 1 for update;
  if not found or o.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'EXPIRED');
  end if;
  if o.attempts >= public.cfg('OTP_MAX_ATTEMPTS') then
    return jsonb_build_object('ok', false, 'error', 'TOO_MANY');
  end if;
  if o.code_hash <> public.sha256_hex(auth.uid()::text || ':' || btrim(coalesce(p_code, ''))) then
    update public.otp_codes set attempts = attempts + 1 where id = o.id;
    return jsonb_build_object('ok', false, 'error',
      case when o.attempts + 1 >= public.cfg('OTP_MAX_ATTEMPTS') then 'TOO_MANY' else 'INVALID' end);
  end if;
  update public.otp_codes set consumed_at = now() where id = o.id;
  insert into public.verified_sessions (session_id, user_id, method) values (sid, auth.uid(), 'OTP_EMAIL')
  on conflict (session_id) do nothing;
  token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.trusted_devices (token_hash, user_id, expires_at)
  values (public.sha256_hex(token), auth.uid(), now() + make_interval(days => public.cfg('TRUST_DAYS')));
  return jsonb_build_object('ok', true, 'device_token', token);
end
$$;

/** หลังเปลี่ยนรหัสผ่านครั้งแรกสำเร็จ (แอปเปลี่ยนผ่าน Supabase Auth แล้วเรียกฟังก์ชันนี้) */
create or replace function public.password_changed() returns void
language sql security definer set search_path = public as $$
  update public.staff set must_change_password = false where user_id = (public.me()).user_id;
$$;

/** ออกจากระบบ: session นี้ใช้ไม่ได้อีก (เครื่องที่จำไว้ยังอยู่ ล็อกอินครั้งหน้าไม่ต้องใช้ OTP) */
create or replace function public.end_session() returns void
language sql security definer set search_path = public as $$
  delete from public.verified_sessions where session_id = public.current_session_id() and user_id = auth.uid();
$$;

-- ---- เรียกได้เฉพาะ Edge Functions (service_role) ----

/**
 * สร้าง OTP ใหม่ (Edge Function เป็นผู้ส่งอีเมล) คืน code หรือ error
 * LOGIN ต้องมี session_id, RESET ใช้อีเมลหา user (ไม่บอกว่ามีอีเมลนี้หรือไม่)
 */
create or replace function public.svc_create_otp(p_purpose text, p_user_id uuid default null, p_session_id uuid default null, p_email text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s public.staff;
  last timestamptz;
  code text := public.random_digits(6);
begin
  if p_purpose = 'LOGIN' then
    select * into s from public.staff where user_id = p_user_id and active;
  else
    select * into s from public.staff where email = lower(btrim(p_email)) and active;
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_USER');
  end if;
  if p_purpose = 'LOGIN' and p_session_id is null then
    return jsonb_build_object('ok', false, 'error', 'NO_SESSION');
  end if;
  select max(created_at) into last from public.otp_codes where user_id = s.user_id and purpose = p_purpose;
  if last is not null and last > now() - make_interval(secs => public.cfg('OTP_RESEND_SEC')) then
    return jsonb_build_object('ok', false, 'error', 'COOLDOWN',
                              'retry_in', ceil(public.cfg('OTP_RESEND_SEC') - extract(epoch from now() - last))::int);
  end if;
  -- รหัสเก่าที่ยังไม่ใช้ของจุดประสงค์เดียวกันใช้ไม่ได้อีก
  update public.otp_codes set consumed_at = now()
   where user_id = s.user_id and purpose = p_purpose and consumed_at is null;
  insert into public.otp_codes (user_id, purpose, session_id, code_hash, expires_at)
  values (s.user_id, p_purpose, p_session_id, public.sha256_hex(s.user_id::text || ':' || code),
          now() + make_interval(mins => public.cfg('OTP_TTL_MIN')));
  return jsonb_build_object('ok', true, 'code', code, 'email', s.email, 'name', s.name, 'ttl_min', public.cfg('OTP_TTL_MIN'));
end
$$;

/** ตรวจ OTP สำหรับลืมรหัสผ่าน คืน user_id ถ้าถูกต้อง (Edge Function ตั้งรหัสผ่านใหม่ต่อ) */
create or replace function public.svc_verify_reset_otp(p_email text, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.staff;
  o public.otp_codes;
begin
  select * into s from public.staff where email = lower(btrim(p_email)) and active;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'INVALID');
  end if;
  select * into o from public.otp_codes
   where user_id = s.user_id and purpose = 'RESET' and consumed_at is null
   order by created_at desc limit 1 for update;
  if not found or o.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'EXPIRED');
  end if;
  if o.attempts >= public.cfg('OTP_MAX_ATTEMPTS') then
    return jsonb_build_object('ok', false, 'error', 'TOO_MANY');
  end if;
  if o.code_hash <> public.sha256_hex(s.user_id::text || ':' || btrim(coalesce(p_code, ''))) then
    update public.otp_codes set attempts = attempts + 1 where id = o.id;
    return jsonb_build_object('ok', false, 'error',
      case when o.attempts + 1 >= public.cfg('OTP_MAX_ATTEMPTS') then 'TOO_MANY' else 'INVALID' end);
  end if;
  update public.otp_codes set consumed_at = now() where id = o.id;
  return jsonb_build_object('ok', true, 'user_id', s.user_id);
end
$$;

/** หลังตั้งรหัสผ่านใหม่: ออกจากระบบทุกเครื่องและล้างเครื่องที่จำไว้ทั้งหมด */
create or replace function public.svc_after_password_reset(p_user_id uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  delete from public.trusted_devices where user_id = p_user_id;
  delete from public.verified_sessions where user_id = p_user_id;
  delete from auth.sessions where user_id = p_user_id;
  update public.staff set must_change_password = false where user_id = p_user_id;
end
$$;

-- ---------------------------------------------------------------------------
-- LINE webhook (เรียกได้เฉพาะ service_role)
-- ---------------------------------------------------------------------------

create or replace function public.line_context(p_user_id text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'session', (select jsonb_build_object('state', state, 'draft', draft, 'version', version)
                  from public.line_sessions where line_user_id = p_user_id),
    'binding', (select jsonb_build_object('room_no', room_no, 'display_name', display_name, 'status', status)
                  from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE'))
$$;

/** บันทึกสถานะบทสนทนาแบบตรวจเวอร์ชัน คืน false ถ้ามีเหตุการณ์อื่นเขียนก่อน (ให้ผู้เรียกอ่านใหม่แล้วลองอีกครั้ง) */
create or replace function public.line_save_session(p_user_id text, p_version int, p_state text, p_draft jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_version is null then
    insert into public.line_sessions (line_user_id, state, draft, version) values (p_user_id, p_state, p_draft, 1)
    on conflict (line_user_id) do nothing;
    return found;
  end if;
  update public.line_sessions set state = p_state, draft = p_draft, version = version + 1, updated_at = now()
   where line_user_id = p_user_id and version = p_version;
  return found;
end
$$;

create or replace function public.line_set_idle(p_user_id text) returns void
language sql security definer set search_path = public as $$
  insert into public.line_sessions (line_user_id, state, draft, version) values (p_user_id, 'IDLE', null, 1)
  on conflict (line_user_id) do update set state = 'IDLE', draft = null, version = line_sessions.version + 1, updated_at = now();
$$;

create or replace function public.line_is_processed(p_event_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.processed_events where event_id = p_event_id)
$$;

create or replace function public.line_mark_processed(p_event_id text) returns void
language sql security definer set search_path = public as $$
  insert into public.processed_events (event_id) values (p_event_id) on conflict do nothing;
$$;

/**
 * ผู้พักพิมพ์รหัสผูกห้อง ผลลัพธ์ result:
 * BOUND (ผูกแล้ว + room_no), INVALID (ผิด/ใช้แล้ว/หมดอายุ), LIMIT (ผิดเกินกำหนดวันนี้), ALREADY (ผูกห้องอยู่แล้ว)
 */
create or replace function public.line_redeem_code(p_user_id text, p_code text, p_display_name text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := public.thai_now()::date;
  ic public.invite_codes;
  b public.line_bindings;
begin
  if coalesce((select failed from public.bind_attempts where line_user_id = p_user_id and day = today), 0)
       >= public.cfg('MAX_BIND_FAILED') then
    return jsonb_build_object('result', 'LIMIT');
  end if;
  -- กันผู้พักคนเดียวส่งรหัสสองรหัสพร้อมกันแล้วได้สองห้อง
  perform pg_advisory_xact_lock(hashtext('bind:' || p_user_id));
  select * into b from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if found then
    return jsonb_build_object('result', 'ALREADY', 'room_no', b.room_no);
  end if;
  select * into ic from public.invite_codes where code_hash = public.sha256_hex(p_code) for update;
  if not found or ic.status <> 'UNUSED' or ic.expires_at <= now() then
    insert into public.bind_attempts (line_user_id, day, failed) values (p_user_id, today, 1)
    on conflict (line_user_id, day) do update set failed = bind_attempts.failed + 1;
    return jsonb_build_object('result', 'INVALID');
  end if;
  update public.invite_codes set status = 'USED', used_by = p_user_id, used_at = now() where code_hash = ic.code_hash;
  insert into public.line_bindings (line_user_id, room_no, display_name, status, bound_at, invite_code_hash)
  values (p_user_id, ic.room_no, coalesce(p_display_name, ''), 'ACTIVE', now(), ic.code_hash);
  return jsonb_build_object('result', 'BOUND', 'room_no', ic.room_no);
end
$$;

create or replace function public.line_ticket_no(p_ticket_id text) returns text
language sql stable security definer set search_path = public as $$
  select ticket_no from public.tickets where id = p_ticket_id
$$;

/**
 * สร้างใบแจ้งซ่อมจากร่าง เรียกซ้ำด้วย ticket_id เดิมได้ใบเดิม (กดยืนยันซ้ำไม่เกิดใบซ้ำ)
 * error = NOT_BOUND ถ้าบัญชีไม่ได้ผูกห้องที่ใช้งานอยู่
 */
create or replace function public.line_create_ticket(p_ticket_id text, p_user_id text, p_category text, p_description text, p_photo_paths text[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b public.line_bindings;
  existing public.tickets;
  yr int := extract(year from public.thai_now())::int + 543;
  seq int;
  no text;
begin
  select * into existing from public.tickets where id = p_ticket_id;
  if found then
    return jsonb_build_object('ticket_no', existing.ticket_no, 'room_no', existing.room_no);
  end if;
  select * into b from public.line_bindings where line_user_id = p_user_id and status = 'ACTIVE';
  if not found then
    return jsonb_build_object('error', 'NOT_BOUND');
  end if;
  insert into public.counters (name, value) values ('tickets-' || yr, 1)
  on conflict (name) do update set value = counters.value + 1
  returning value into seq;
  no := 'R' || yr || '-' || lpad(seq::text, 4, '0');
  insert into public.tickets (id, ticket_no, room_no, line_user_id, binding_id, reporter_name, category, description, photo_paths)
  values (p_ticket_id, no, b.room_no, p_user_id, b.id, b.display_name, p_category, p_description, coalesce(p_photo_paths, '{}'));
  insert into public.ticket_history (ticket_id, action, from_status, to_status, actor_name, actor_role, note)
  values (p_ticket_id, 'CREATE', null, 'PENDING', b.display_name, 'RESIDENT', 'ผู้พักแจ้งซ่อมผ่าน LINE');
  return jsonb_build_object('ticket_no', no, 'room_no', b.room_no);
exception when unique_violation then
  -- คำขอซ้ำที่มาพร้อมกันสร้างใบไปก่อนแล้ว
  select * into existing from public.tickets where id = p_ticket_id;
  return jsonb_build_object('ticket_no', existing.ticket_no, 'room_no', existing.room_no);
end
$$;

create or replace function public.line_recent_tickets(p_room_no text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (
    select ticket_no, category, status, assigned_to is not null as assigned, created_at
      from public.tickets where room_no = p_room_no order by created_at desc limit 5
  ) x
$$;

create or replace function public.line_contact_text() returns text
language sql stable security definer set search_path = public as $$
  select value from public.settings where key = 'contact_text'
$$;

-- ---------------------------------------------------------------------------
-- สิทธิ์การเรียกฟังก์ชัน
-- ---------------------------------------------------------------------------

-- ฟังก์ชันช่วยภายในที่เป็น security definer (เช่น lock_ticket, add_history) ห้ามให้แอปเรียกตรง
-- จึงเปิดให้ authenticated เฉพาะรายชื่อด้านล่าง ที่เหลือเรียกได้จากในฟังก์ชันอื่นเท่านั้น
do $$
declare
  f record;
  app_callable text[] := array[
    'me', 'is_admin', 'is_staff',                                   -- ใช้ใน RLS policy
    'assign_ticket', 'start_repair', 'submit_result', 'begin_notify', 'finish_notify',
    'create_invite_code', 'revoke_binding',
    'auth_status', 'verify_trusted_device', 'verify_login_otp', 'password_changed', 'end_session'];
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
    if f.proname = any (app_callable) then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- RLS: อ่านได้ตามบทบาท เขียนผ่านฟังก์ชันเท่านั้น
-- ---------------------------------------------------------------------------

alter table public.staff enable row level security;
alter table public.rooms enable row level security;
alter table public.settings enable row level security;
alter table public.invite_codes enable row level security;
alter table public.line_bindings enable row level security;
alter table public.bind_attempts enable row level security;
alter table public.line_sessions enable row level security;
alter table public.processed_events enable row level security;
alter table public.counters enable row level security;
alter table public.tickets enable row level security;
alter table public.ticket_history enable row level security;
alter table public.notifications enable row level security;
alter table public.verified_sessions enable row level security;
alter table public.trusted_devices enable row level security;
alter table public.otp_codes enable row level security;

create policy staff_read on public.staff for select to authenticated
  using (public.is_admin() or user_id = (public.me()).user_id);
create policy rooms_read on public.rooms for select to authenticated using (public.is_staff());
create policy settings_read on public.settings for select to authenticated using (public.is_staff());
create policy bindings_read on public.line_bindings for select to authenticated using (public.is_admin());
create policy tickets_read on public.tickets for select to authenticated
  using (public.is_admin() or (assigned_to = (public.me()).user_id));
create policy history_read on public.ticket_history for select to authenticated
  using (exists (select 1 from public.tickets t where t.id = ticket_id
                  and (public.is_admin() or t.assigned_to = (public.me()).user_id)));

-- Supabase ให้สิทธิ์ตารางใหม่กับ anon และ authenticated ไว้ทั้งหมดโดยปริยาย ถอนออกก่อน แล้วให้เฉพาะการอ่าน
revoke all on all tables in schema public from anon, authenticated;
grant select on public.staff, public.rooms, public.settings, public.line_bindings, public.tickets, public.ticket_history to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- realtime สำหรับรายการงานในแอป
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.tickets, public.ticket_history, public.line_bindings;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Storage: รูปจากผู้พัก (Edge Function เขียน) และรูปหลังซ่อม (ช่างอัปโหลด)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('resident-photos', 'resident-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
       ('repair-photos', 'repair-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- path ของทั้งสอง bucket ขึ้นต้นด้วย {ticket_id}/
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id in ('resident-photos', 'repair-photos')
         and exists (select 1 from public.tickets t where t.id = (storage.foldername(name))[1]
                      and (public.is_admin() or t.assigned_to = (public.me()).user_id)));

create policy repair_photos_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'repair-photos'
              and exists (select 1 from public.tickets t where t.id = (storage.foldername(name))[1]
                           and t.status = 'REPAIRING' and t.assigned_to = (public.me()).user_id));
