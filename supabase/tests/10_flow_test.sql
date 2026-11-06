-- ทดสอบ migration บน Postgres ในเครื่อง: psql -v ON_ERROR_STOP=1 -f 00_stub_supabase.sql -f ../migrations/... -f 10_flow_test.sql
-- ทุก assert ล้มจะหยุดสคริปต์ทันที

\set admin   '''aaaaaaaa-0000-0000-0000-000000000001'''
\set tech    '''aaaaaaaa-0000-0000-0000-000000000002'''
\set tech2   '''aaaaaaaa-0000-0000-0000-000000000003'''
\set s_admin '''bbbbbbbb-0000-0000-0000-000000000001'''
\set s_tech  '''bbbbbbbb-0000-0000-0000-000000000002'''
\set s_tech2 '''bbbbbbbb-0000-0000-0000-000000000003'''
\set s_new   '''bbbbbbbb-0000-0000-0000-000000000009'''

create or replace function pg_temp.as_user(p_uid text, p_sid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'session_id', p_sid, 'role', 'authenticated')::text, false);
$$;

create or replace function pg_temp.expect_error(p_sql text, p_hint text) returns void language plpgsql as $$
declare h text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics h = pg_exception_hint;
    if p_hint is not null and h is distinct from p_hint then
      raise exception 'expected hint % but got % (%)', p_hint, h, sqlerrm;
    end if;
    return;
  end;
  raise exception 'expected error from: %', p_sql;
end $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---- ข้อมูลตั้งต้น ----
insert into auth.users (id, email) values (:admin, 'admin@dorm.test'), (:tech, 'tech@dorm.test'), (:tech2, 'tech2@dorm.test');
insert into auth.sessions (id, user_id) values (:s_admin, :admin), (:s_tech, :tech), (:s_tech2, :tech2);
insert into public.staff (user_id, email, name, role) values
  (:admin, 'admin@dorm.test', 'ผู้ดูแล', 'ADMIN'),
  (:tech, 'tech@dorm.test', 'ช่างหนึ่ง', 'TECHNICIAN'),
  (:tech2, 'tech2@dorm.test', 'ช่างสอง', 'TECHNICIAN');
insert into public.rooms (room_no) values ('101'), ('102');
insert into public.settings values ('contact_text', 'ติดต่อสำนักงานหอพัก');

-- ---- 1. session ที่ยังไม่ผ่าน OTP อ่านและแก้อะไรไม่ได้ ----
select pg_temp.as_user(:admin, :s_admin);
set role authenticated;
do $$ begin
  assert (public.auth_status() ->> 'verified')::boolean = false, 'should be unverified';
  assert (public.auth_status() ->> 'email_masked') = 'a****@dorm.test', 'mask: ' || (public.auth_status() ->> 'email_masked');
  assert (select count(*) from public.rooms) = 0, 'unverified should not read rooms';
end $$;
select pg_temp.expect_error($$select public.create_invite_code('101')$$, 'unauthenticated');
select pg_temp.expect_error($$select public.svc_create_otp('LOGIN', auth.uid(), public.current_session_id())$$, null);
select pg_temp.expect_error($$insert into public.rooms values ('999')$$, null);
select pg_temp.expect_error($$select public.lock_ticket('r_1')$$, null);
select pg_temp.expect_error($$select public.random_digits(6)$$, null);
reset role;

-- ---- 2. OTP ตอนล็อกอิน ----
set role service_role;
select (public.svc_create_otp('LOGIN', :admin, :s_admin)) ->> 'code' as otp_admin \gset
do $$ begin
  assert (public.svc_create_otp('LOGIN', 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001') ->> 'error') = 'COOLDOWN', 'resend cooldown';
  assert (public.svc_create_otp('RESET', null, null, 'nobody@dorm.test') ->> 'error') = 'NO_USER', 'unknown email';
end $$;
reset role;

select pg_temp.as_user(:admin, :s_admin);
set role authenticated;
select (public.verify_login_otp('000000') ->> 'error') = 'INVALID' or :'otp_admin' = '000000' as wrong_code_rejected \gset
\if :wrong_code_rejected
\else
  \echo 'FAIL wrong code'
  select 1/0;
\endif
select public.verify_login_otp(:'otp_admin') ->> 'device_token' as device_token \gset
do $$ begin
  assert (public.auth_status() ->> 'verified')::boolean, 'should be verified after OTP';
  assert public.is_admin(), 'admin role';
  assert (select count(*) from public.rooms) = 2, 'verified admin reads rooms';
end $$;
-- ใช้รหัสเดิมซ้ำไม่ได้
select pg_temp.expect_error($$select 1/((public.verify_login_otp('x') ->> 'ok')::boolean::int)$$, null);
reset role;

-- ---- 3. เครื่องที่จำไว้: session ใหม่ไม่ต้องใช้ OTP ----
select pg_temp.as_user(:admin, :s_new);
set role authenticated;
do $$ begin
  assert not public.is_staff(), 'new session starts unverified';
  assert not public.verify_trusted_device('wrong-token'), 'bad token rejected';
end $$;
select public.verify_trusted_device(:'device_token') as trusted \gset
\if :trusted
\else
  \echo 'FAIL trusted device'
  select 1/0;
\endif
do $$ begin assert public.is_admin(), 'trusted session verified'; end $$;
reset role;

-- ช่างทั้งสองยืนยันด้วย OTP
set role service_role;
select (public.svc_create_otp('LOGIN', :tech, :s_tech)) ->> 'code' as otp_tech \gset
select (public.svc_create_otp('LOGIN', :tech2, :s_tech2)) ->> 'code' as otp_tech2 \gset
reset role;
set role authenticated;
select pg_temp.as_user(:tech, :s_tech);
select public.verify_login_otp(:'otp_tech') ->> 'ok' as ok1 \gset
select pg_temp.as_user(:tech2, :s_tech2);
select public.verify_login_otp(:'otp_tech2') ->> 'ok' as ok2 \gset
reset role;

-- ---- 4. ผูกห้องด้วยรหัส ----
select pg_temp.as_user(:tech, :s_tech);
set role authenticated;
select pg_temp.expect_error($$select public.create_invite_code('101')$$, 'permission-denied');
select pg_temp.as_user(:admin, :s_admin);
select public.create_invite_code('101') ->> 'code' as invite \gset
select pg_temp.expect_error($$select public.create_invite_code('999')$$, 'not-found');
reset role;

set role service_role;
do $$ declare r jsonb; begin
  for i in 1..4 loop
    r := public.line_redeem_code('Ubad', '000000');
    assert r ->> 'result' = 'INVALID', 'bad code ' || i;
  end loop;
  perform public.line_redeem_code('Ubad', '000000');
  assert public.line_redeem_code('Ubad', '000000') ->> 'result' = 'LIMIT', 'daily limit';
end $$;
select public.line_redeem_code('U1', :'invite', 'สมชาย') ->> 'result' as bound \gset
select public.line_redeem_code('U2', :'invite') ->> 'result' as reused \gset
do $$ begin
  assert (select status from public.line_bindings where line_user_id = 'U1') = 'ACTIVE', 'binding active';
  assert public.line_redeem_code('U1', '123456') ->> 'result' = 'ALREADY', 'already bound';
end $$;
reset role;
\if `test :bound = BOUND -a :reused = INVALID && echo 1 || echo 0`
\else
  \echo 'FAIL redeem' :bound :reused
  select 1/0;
\endif

-- ---- 5. สร้างใบแจ้งซ่อมจาก LINE ----
set role service_role;
do $$ declare a jsonb; b jsonb; yr int := extract(year from now() at time zone 'Asia/Bangkok')::int + 543; begin
  assert public.line_create_ticket('r_x', 'Unobody', 'PLUMBING', 'น้ำรั่ว') ->> 'error' = 'NOT_BOUND', 'unbound';
  a := public.line_create_ticket('r_1', 'U1', 'PLUMBING', 'ก๊อกน้ำรั่ว');
  b := public.line_create_ticket('r_1', 'U1', 'PLUMBING', 'ก๊อกน้ำรั่ว');
  assert a ->> 'ticket_no' = 'R' || yr || '-0001', 'ticket no ' || (a ->> 'ticket_no');
  assert a = b, 'confirm twice returns same ticket';
  assert public.line_create_ticket('r_2', 'U1', 'ELECTRICAL', 'ไฟดับ') ->> 'ticket_no' = 'R' || yr || '-0002', 'second ticket';
  assert (select count(*) from public.ticket_history where ticket_id = 'r_1') = 1, 'one CREATE history';
  assert jsonb_array_length(public.line_recent_tickets('101')) = 2, 'recent list';
  assert public.line_contact_text() = 'ติดต่อสำนักงานหอพัก', 'contact';
end $$;
-- session แบบตรวจเวอร์ชัน
do $$ begin
  assert public.line_save_session('U1', null, 'REPORT_CATEGORY', '{}'), 'create session';
  assert not public.line_save_session('U1', null, 'REPORT_CATEGORY', '{}'), 'second create loses';
  assert public.line_save_session('U1', 1, 'REPORT_DETAIL', '{}'), 'update v1';
  assert not public.line_save_session('U1', 1, 'REPORT_PHOTO', '{}'), 'stale version rejected';
  perform public.line_mark_processed('ev1');
  assert public.line_is_processed('ev1') and not public.line_is_processed('ev2'), 'processed events';
end $$;
reset role;

-- ---- 6. มอบหมาย ซ่อม และบันทึกผล ----
set role authenticated;
select pg_temp.as_user(:tech, :s_tech);
do $$ begin assert (select count(*) from public.tickets) = 0, 'tech sees nothing before assignment'; end $$;
select pg_temp.as_user(:admin, :s_admin);
do $$ begin assert (select count(*) from public.tickets) = 2, 'admin sees all'; end $$;
select pg_temp.expect_error($$select public.assign_ticket('r_1', 'aaaaaaaa-0000-0000-0000-000000000001')$$, 'invalid-argument');
select public.assign_ticket('r_1', :tech2);
select public.assign_ticket('r_1', :tech);
do $$ begin
  assert (select array_agg(action order by id) from public.ticket_history where ticket_id = 'r_1') = '{CREATE,ASSIGN,REASSIGN}', 'assign history';
end $$;

select pg_temp.as_user(:tech2, :s_tech2);
do $$ begin assert (select count(*) from public.tickets) = 0, 'tech2 lost the ticket after reassign'; end $$;
select pg_temp.expect_error($$select public.start_repair('r_1')$$, 'permission-denied');

select pg_temp.as_user(:tech, :s_tech);
do $$ begin assert (select count(*) from public.tickets) = 1, 'tech sees assigned ticket'; end $$;
select pg_temp.expect_error($$select public.submit_result('r_1', 'a', 'b')$$, 'failed-precondition');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('repair-photos', 'r_1/a.jpg')$$, null);
select public.start_repair('r_1');
insert into storage.objects (bucket_id, name) values ('repair-photos', 'r_1/a.jpg');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('repair-photos', 'r_2/a.jpg')$$, null);
select pg_temp.expect_error($$select public.submit_result('r_1', ' ', 'b')$$, 'invalid-argument');
select pg_temp.expect_error($$select public.submit_result('r_1', 'a', 'b', array['r_2/a.jpg'])$$, 'invalid-argument');
select pg_temp.expect_error($$select public.submit_result('r_1', 'a', 'b', array['r_1/1','r_1/2','r_1/3','r_1/4'])$$, 'invalid-argument');
select pg_temp.expect_error($$update public.tickets set status = 'COMPLETED' where id = 'r_1'$$, null);
select public.submit_result('r_1', 'ซีลยางเสื่อม', 'เปลี่ยนซีลยางแล้ว', array['r_1/a.jpg']);
do $$ begin
  assert (select status = 'COMPLETED' and awaiting_notify and not is_open from public.tickets where id = 'r_1'), 'completed';
  assert (select count(*) from storage.objects where name like 'r_1/%') = 1, 'tech can read own photo';
end $$;
select pg_temp.expect_error($$select public.begin_notify('r_1', gen_random_uuid())$$, 'permission-denied');

-- ---- 7. ผู้ดูแลแจ้งผลทาง LINE ----
select pg_temp.as_user(:admin, :s_admin);
select pg_temp.expect_error($$select public.begin_notify('r_2', gen_random_uuid())$$, 'failed-precondition');
do $$ declare rid uuid := gen_random_uuid(); r jsonb; begin
  r := public.begin_notify('r_1', rid);
  assert r ->> 'action' = 'SEND' and r -> 'ticket' ->> 'line_user_id' = 'U1', 'begin notify';
  perform public.finish_notify(rid, false, 'timeout');
  assert public.begin_notify('r_1', rid) ->> 'action' = 'SEND', 'retry after failure';
  perform public.finish_notify(rid, true);
  perform public.finish_notify(rid, true);
  assert public.begin_notify('r_1', rid) ->> 'action' = 'DUPLICATE', 'duplicate';
  assert (select not awaiting_notify and notified_at is not null from public.tickets where id = 'r_1'), 'notified';
  assert (select count(*) from public.ticket_history where ticket_id = 'r_1' and action = 'NOTIFY_LINE') = 1, 'one notify history';
end $$;

-- ---- 8. ยกเลิกผูกห้อง ----
select public.revoke_binding('U1');
select pg_temp.expect_error($$select public.revoke_binding('U1')$$, 'failed-precondition');
reset role;
set role service_role;
do $$ begin
  assert public.line_create_ticket('r_3', 'U1', 'OTHER', 'x') ->> 'error' = 'NOT_BOUND', 'revoked cannot report';
end $$;
reset role;

set role service_role;
-- ---- ย้ายห้อง: ผูกใหม่ได้รายการใหม่ ประวัติเดิมยังอยู่ และใบงานเก่าชี้ไปที่การผูกเดิม ----
reset role;
select pg_temp.as_user(:admin, :s_admin);
set role authenticated;
select public.create_invite_code('102') ->> 'code' as invite2 \gset
reset role;
set role service_role;
select public.line_redeem_code('U1', :'invite2', 'สมชาย') ->> 'room_no' as new_room \gset
do $$ begin
  assert (select count(*) from public.line_bindings where line_user_id = 'U1') = 2, 'two binding rows';
  assert (select count(*) from public.line_bindings where line_user_id = 'U1' and status = 'ACTIVE') = 1, 'one active';
  assert (select room_no from public.line_bindings where line_user_id = 'U1' and status = 'REVOKED') = '101', 'old row kept';
  assert (select b.room_no from public.tickets t join public.line_bindings b on b.id = t.binding_id where t.id = 'r_1') = '101', 'ticket keeps old binding';
  assert public.line_context('U1') -> 'binding' ->> 'room_no' = '102', 'context shows active binding';
  begin
    insert into public.line_bindings (line_user_id, room_no, status) values ('U1', '101', 'ACTIVE');
    raise exception 'second active binding allowed';
  exception when unique_violation then null;
  end;
end $$;
reset role;
\if `test :new_room = 102 && echo 1 || echo 0`
\else
  \echo 'FAIL rebind' :new_room
  select 1/0;
\endif
set role service_role;

-- ---- 9. ลืมรหัสผ่าน ----
select (public.svc_create_otp('RESET', null, null, 'ADMIN@dorm.test')) ->> 'code' as reset_code \gset
do $$ begin
  assert public.svc_verify_reset_otp('admin@dorm.test', 'abc') ->> 'error' = 'INVALID', 'reset wrong code';
end $$;
select public.svc_verify_reset_otp('admin@dorm.test', :'reset_code') ->> 'user_id' as reset_uid \gset
select public.svc_after_password_reset(:'reset_uid');
do $$ begin
  assert (select count(*) from public.trusted_devices where user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'devices cleared';
  assert (select count(*) from public.verified_sessions where user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'sessions cleared';
  assert (select count(*) from auth.sessions where user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'auth sessions cleared';
  assert public.svc_verify_reset_otp('admin@dorm.test', 'x') ->> 'error' = 'EXPIRED', 'reset code single use';
end $$;
reset role;

select pg_temp.as_user(:admin, :s_admin);
set role authenticated;
do $$ begin assert not public.is_staff(), 'old session dead after reset'; end $$;
reset role;

\echo 'ALL TESTS PASSED'
