insert into public.rooms (room_no) values ('P1-01') on conflict do nothing;
insert into public.invite_codes (code_hash, room_no, status, expires_at) values (public.sha256_hex('654321'), 'P1-01', 'UNUSED', now() + interval '1 day');
do $$ begin if public.line_redeem_code('Upriv', '654321', 'ผู้พัก', '2026-11-22')->>'result' <> 'BOUND' then raise exception 'bind with privacy'; end if; end $$;
do $$ begin if not exists (select 1 from public.line_bindings where line_user_id = 'Upriv' and privacy_version = '2026-11-22' and privacy_ack_at is not null) then raise exception 'privacy recorded'; end if; end $$;
insert into public.tickets (id, ticket_no, room_no, line_user_id, category, description, status) values
  ('fb_1', 'R2569-9001', 'P1-01', 'Upriv', 'PLUMBING', 'ก๊อกรั่ว', 'COMPLETED'),
  ('fb_2', 'R2569-9002', 'P1-01', 'Upriv', 'ELECTRICAL', 'ไฟดับ', 'PENDING');
do $$ begin if public.line_rate_ticket('Uother', 'fb_1', 5)->>'result' <> 'NOT_FOUND' then raise exception 'other user'; end if; end $$;
do $$ begin if public.line_rate_ticket('Upriv', 'fb_2', 5)->>'result' <> 'NOT_COMPLETED' then raise exception 'not completed'; end if; end $$;
do $$ begin if public.line_rate_ticket('Upriv', 'fb_1', 6)->>'result' <> 'INVALID' or public.line_rate_ticket('Upriv', 'fb_1')->>'result' <> 'INVALID' then raise exception 'rating range'; end if; end $$;
do $$ begin if public.line_rate_ticket('Upriv', 'fb_1', 4)->>'result' <> 'OK' then raise exception 'rate'; end if; end $$;
do $$ begin if (select resident_rating from public.tickets where id = 'fb_1') <> 4 then raise exception 'rating saved'; end if; end $$;
do $$ begin if (public.line_rate_ticket('Upriv', 'fb_1', null, true)->>'first_issue')::boolean is not true then raise exception 'first issue'; end if; end $$;
do $$ begin if (public.line_rate_ticket('Upriv', 'fb_1', null, true)->>'first_issue')::boolean then raise exception 'repeat issue'; end if; end $$;
do $$ begin if not (select resident_issue from public.tickets where id = 'fb_1') then raise exception 'issue saved'; end if; end $$;
do $$ begin if (select count(*) from public.ticket_history where ticket_id = 'fb_1' and action in ('RESIDENT_RATE', 'RESIDENT_ISSUE')) <> 3 then raise exception 'history'; end if; end $$;
