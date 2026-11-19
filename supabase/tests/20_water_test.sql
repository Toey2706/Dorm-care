\set admin   '''cccccccc-0000-0000-0000-000000000001'''
\set tech    '''cccccccc-0000-0000-0000-000000000002'''
create or replace function pg_temp.as_user(p_uid text, p_sid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'session_id', p_sid, 'role', 'authenticated')::text, false);
$$;
create or replace function pg_temp.first_alert() returns bigint language sql as $$ select min(id) from public.water_alerts $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
insert into auth.users (id, email) values (:admin, 'wa@x'), (:tech, 'wt@x');
insert into auth.sessions (id, user_id) values ('dddddddd-0000-0000-0000-000000000001', :admin), ('dddddddd-0000-0000-0000-000000000002', :tech);
insert into public.staff (user_id, email, name, role) values (:admin, 'wa@x', 'Admin', 'ADMIN'), (:tech, 'wt@x', 'Tech', 'TECHNICIAN');
insert into public.verified_sessions (session_id, user_id, method) select id, user_id, 'OTP_EMAIL' from auth.sessions where user_id in (:admin, :tech);
insert into public.rooms (room_no) values ('A1-01') on conflict do nothing;
insert into public.water_devices (id, room_no, tb_device_id) values ('WF-001','A1-01','8c5a0c30-e40f-11f1-a048-89a8198d067e') on conflict do nothing;
insert into public.water_alerts (room_no, minutes) values ('A1-01', 12);
set role authenticated;
select pg_temp.as_user(:tech, 'dddddddd-0000-0000-0000-000000000002');
do $$ begin if (select count(*) from public.water_alerts) <> 0 then raise exception 'tech sees alerts'; end if; end $$;
do $$ begin begin perform public.close_water_alert(pg_temp.first_alert(), 'LEAK'); raise exception 'tech acked'; exception when others then if sqlerrm = 'tech acked' then raise; end if; end; end $$;
select pg_temp.as_user(:admin, 'dddddddd-0000-0000-0000-000000000001');
do $$ begin if (select count(*) from public.water_devices) <> 1 then raise exception 'admin cannot see devices'; end if; end $$;
select public.close_water_alert(pg_temp.first_alert(), 'LEAK');
do $$ begin if (select acked_name || result from public.water_alerts where id=pg_temp.first_alert()) <> 'AdminLEAK' then raise exception 'close not saved'; end if; end $$;
do $$ declare h text; begin begin perform public.close_water_alert(pg_temp.first_alert(), 'LEAK'); exception when others then get stacked diagnostics h = pg_exception_hint; end; if h is distinct from 'failed-precondition' then raise exception 'double ack hint %', h; end if; end $$;
do $$ declare h text; begin begin perform public.close_water_alert(99, 'NORMAL'); exception when others then get stacked diagnostics h = pg_exception_hint; end; if h is distinct from 'not-found' then raise exception 'missing hint %', h; end if; end $$;
do $$ begin begin update public.water_alerts set minutes = 1; raise exception 'direct update allowed'; exception when insufficient_privilege then null; end; end $$;
reset role;
insert into public.water_alerts (room_no) values ('A1-01');
set role authenticated;
select pg_temp.as_user(:admin, 'dddddddd-0000-0000-0000-000000000001');
do $$ declare h text; begin begin perform public.close_water_alert((select max(id) from public.water_alerts), 'OTHER'); exception when others then get stacked diagnostics h = pg_exception_hint; end; if h is distinct from 'invalid-argument' then raise exception 'bad result hint %', h; end if; end $$;
reset role;
select 'water ok';
