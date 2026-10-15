begin;

create function public.create_scoped_invitation(
  target_game_id uuid,
  invitation_type public.invitation_kind,
  validity interval default interval '30 days',
  allowed_uses integer default 1
) returns text
language plpgsql security definer set search_path = ''
as $$
declare raw_token text;
begin
  if not public.owns_game(target_game_id) then raise exception 'forbidden'; end if;
  if validity <= interval '0 seconds' or validity > interval '1 year' then raise exception 'invalid_expiry'; end if;
  if allowed_uses < 1 or allowed_uses > 500 then raise exception 'invalid_uses'; end if;
  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invitations(game_id, kind, token_digest, permissions, max_uses, expires_at, created_by)
  values (
    target_game_id, invitation_type, extensions.digest(raw_token, 'sha256'),
    case when invitation_type = 'contributor' then array['submit']::text[] else array['redeem']::text[] end,
    allowed_uses, now() + validity, auth.uid()
  );
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type)
  values (target_game_id, auth.uid(), 'organizer', 'invitation.created', invitation_type::text);
  return raw_token;
end $$;
revoke all on function public.create_scoped_invitation(uuid, public.invitation_kind, interval, integer) from public, anon;
grant execute on function public.create_scoped_invitation(uuid, public.invitation_kind, interval, integer) to authenticated;

create function public.publish_game(target_game_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare target public.games%rowtype;
begin
  if not public.owns_game(target_game_id) then raise exception 'forbidden'; end if;
  select * into target from public.games where id = target_game_id for update;
  if target.finale_title is null or target.finale_letter is null then raise exception 'finale_required'; end if;
  if not exists(select 1 from public.locations where game_id = target_game_id and state <> 'archived') then
    raise exception 'location_required';
  end if;
  update public.locations set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.characters set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.friend_messages set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.landmarks set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.games set state = 'published', published_at = coalesce(published_at, now()) where id = target_game_id;
  insert into public.audit_events(game_id, actor_id, actor_type, action)
  values (target_game_id, auth.uid(), 'organizer', 'game.published');
end $$;
revoke all on function public.publish_game(uuid) from public, anon;
grant execute on function public.publish_game(uuid) to authenticated;

commit;
