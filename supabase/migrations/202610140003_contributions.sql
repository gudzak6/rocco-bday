begin;

create function public.create_contribution(
  invitation_token_digest bytea,
  contributor_name text,
  birthday_message text,
  suggested_location text,
  suggested_memory text,
  suggested_character text,
  request_fingerprint text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare invite public.invitations%rowtype;
declare submission_id uuid;
declare recent_count integer;
begin
  select count(*) into recent_count from public.audit_events
  where action = 'submission.created'
    and metadata->>'fingerprint' = request_fingerprint
    and created_at > now() - interval '1 hour';
  if recent_count >= 5 then raise exception 'rate_limited' using errcode = 'P0001'; end if;

  select * into invite from public.invitations
  where token_digest = invitation_token_digest and kind = 'contributor'
  for update;
  if not found or invite.revoked_at is not null or invite.expires_at <= now()
    or invite.use_count >= invite.max_uses or not ('submit' = any(invite.permissions)) then
    raise exception 'invalid_invitation' using errcode = 'P0001';
  end if;

  insert into public.submissions(
    game_id, invitation_id, display_name, message,
    location_suggestion, memory_suggestion, character_idea
  ) values (
    invite.game_id, invite.id, left(trim(contributor_name), 80), left(trim(birthday_message), 5000),
    nullif(left(trim(suggested_location), 500), ''),
    nullif(left(trim(suggested_memory), 2000), ''),
    nullif(left(trim(suggested_character), 1000), '')
  ) returning id into submission_id;
  update public.invitations set use_count = use_count + 1 where id = invite.id;
  insert into public.audit_events(game_id, actor_type, action, target_type, target_id, metadata)
  values (invite.game_id, 'contributor', 'submission.created', 'submission', submission_id,
    jsonb_build_object('fingerprint', request_fingerprint));
  return submission_id;
end $$;
revoke all on function public.create_contribution(bytea, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.create_contribution(bytea, text, text, text, text, text, text) to service_role;

commit;
