alter table public.line_bindings
  add column if not exists privacy_version text,
  add column if not exists privacy_ack_at timestamptz;

alter table public.tickets
  add column if not exists resident_rating smallint check (resident_rating between 1 and 5),
  add column if not exists resident_issue boolean not null default false,
  add column if not exists resident_feedback_at timestamptz;

drop function if exists public.line_redeem_code(text, text, text);

create or replace function public.line_redeem_code(p_user_id text, p_code text, p_display_name text default '', p_privacy_version text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  today date := public.thai_now()::date;
  ic public.invite_codes;
  b public.line_bindings;
begin
  if coalesce((select failed from public.bind_attempts where line_user_id = p_user_id and day = today), 0)
       >= public.cfg('MAX_BIND_FAILED') then
    return jsonb_build_object('result', 'LIMIT');
  end if;
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
  insert into public.line_bindings (line_user_id, room_no, display_name, status, bound_at, invite_code_hash, privacy_version, privacy_ack_at)
  values (p_user_id, ic.room_no, coalesce(p_display_name, ''), 'ACTIVE', now(), ic.code_hash,
          p_privacy_version, case when p_privacy_version is null then null else now() end);
  return jsonb_build_object('result', 'BOUND', 'room_no', ic.room_no);
end
$$;

revoke all on function public.line_redeem_code(text, text, text, text) from public, anon, authenticated;
grant execute on function public.line_redeem_code(text, text, text, text) to service_role;

create or replace function public.line_rate_ticket(p_user_id text, p_ticket_id text, p_rating int default null, p_issue boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t public.tickets;
begin
  if not coalesce(p_issue, false) and (p_rating is null or p_rating not between 1 and 5) then
    return jsonb_build_object('result', 'INVALID');
  end if;
  select * into t from public.tickets where id = p_ticket_id and line_user_id = p_user_id for update;
  if not found then
    return jsonb_build_object('result', 'NOT_FOUND');
  end if;
  if t.status <> 'COMPLETED' then
    return jsonb_build_object('result', 'NOT_COMPLETED', 'ticket_no', t.ticket_no);
  end if;
  if coalesce(p_issue, false) then
    update public.tickets set resident_issue = true, resident_feedback_at = now(), updated_at = now() where id = t.id;
    insert into public.ticket_history (ticket_id, action, from_status, to_status, actor_name, actor_role, note)
    values (t.id, 'RESIDENT_ISSUE', t.status, t.status, t.reporter_name, 'RESIDENT', 'ผู้พักแจ้งว่ายังมีปัญหาอยู่');
  else
    update public.tickets set resident_rating = p_rating, resident_feedback_at = now(), updated_at = now() where id = t.id;
    insert into public.ticket_history (ticket_id, action, from_status, to_status, actor_name, actor_role, note)
    values (t.id, 'RESIDENT_RATE', t.status, t.status, t.reporter_name, 'RESIDENT', 'ให้คะแนน ' || p_rating || '/5');
  end if;
  return jsonb_build_object('result', 'OK', 'id', t.id, 'ticket_no', t.ticket_no, 'room_no', t.room_no, 'category', t.category,
                            'first_issue', coalesce(p_issue, false) and not t.resident_issue);
end
$$;

revoke all on function public.line_rate_ticket(text, text, int, boolean) from public, anon, authenticated;
grant execute on function public.line_rate_ticket(text, text, int, boolean) to service_role;
