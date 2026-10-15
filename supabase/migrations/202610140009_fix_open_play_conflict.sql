begin;

create or replace function public.join_open_game(
  new_access_token_digest bytea,
  target_installation_id uuid,
  device_name text
) returns table(player_id uuid, game_id uuid, recipient_name text)
language plpgsql security definer set search_path = ''
as $$
declare game public.games%rowtype;
declare player public.player_identities%rowtype;
begin
  select * into game from public.games
    where state = 'published' and open_play = true
      and (launch_at is null or launch_at <= now())
    order by published_at desc nulls last, updated_at desc
    limit 1;
  if not found then raise exception 'game_unavailable' using errcode = 'P0001'; end if;

  insert into public.player_identities(game_id, display_name, access_token_digest)
  values (game.id, game.recipient_name, new_access_token_digest)
  on conflict on constraint player_identities_game_id_key do update set
    access_token_digest = excluded.access_token_digest,
    access_token_rotated_at = now()
  returning * into player;

  insert into public.player_devices(player_id, installation_id, name)
  values (player.id, target_installation_id, left(device_name, 120))
  on conflict on constraint player_devices_player_id_installation_id_key do update set
    name = excluded.name, revoked_at = null, last_seen_at = now();

  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (game.id, player.id, 'player', 'open_play.joined', 'player_identity', player.id);

  return query select player.id, game.id, game.recipient_name;
end $$;

create or replace function public.redeem_player_invitation(
  invitation_token_digest bytea,
  new_access_token_digest bytea,
  target_installation_id uuid,
  device_name text
) returns table(player_id uuid, game_id uuid, recipient_name text)
language plpgsql security definer set search_path = ''
as $$
declare invite public.invitations%rowtype;
declare game public.games%rowtype;
declare player public.player_identities%rowtype;
begin
  select * into invite from public.invitations
  where token_digest = invitation_token_digest and kind = 'player'
  for update;
  if not found or invite.revoked_at is not null or invite.expires_at <= now() or invite.use_count >= invite.max_uses then
    raise exception 'invalid_invitation' using errcode = 'P0001';
  end if;

  select * into game from public.games where id = invite.game_id and state = 'published';
  if not found then raise exception 'game_unavailable' using errcode = 'P0001'; end if;

  insert into public.player_identities(game_id, display_name, access_token_digest)
  values (game.id, game.recipient_name, new_access_token_digest)
  on conflict on constraint player_identities_game_id_key do update set
    access_token_digest = excluded.access_token_digest,
    access_token_rotated_at = now()
  returning * into player;

  insert into public.player_devices(player_id, installation_id, name)
  values (player.id, target_installation_id, left(device_name, 120))
  on conflict on constraint player_devices_player_id_installation_id_key do update set
    name = excluded.name, revoked_at = null, last_seen_at = now();

  update public.invitations set use_count = use_count + 1 where id = invite.id;
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (game.id, player.id, 'player', 'invitation.redeemed', 'player_identity', player.id);

  return query select player.id, game.id, game.recipient_name;
end $$;

create or replace function public.redeem_player_recovery(
  recovery_token_digest bytea,
  new_access_token_digest bytea,
  target_installation_id uuid,
  device_name text
) returns table(player_id uuid, game_id uuid, recipient_name text)
language plpgsql security definer set search_path = ''
as $$
declare recovery public.recovery_tokens%rowtype;
declare player public.player_identities%rowtype;
declare game public.games%rowtype;
begin
  select * into recovery from public.recovery_tokens
  where token_digest = recovery_token_digest for update;
  if not found or recovery.used_at is not null or recovery.revoked_at is not null or recovery.expires_at <= now() then
    raise exception 'invalid_recovery' using errcode = 'P0001';
  end if;
  select * into player from public.player_identities where id = recovery.player_id for update;
  select * into game from public.games where id = player.game_id and state = 'published';
  if not found then raise exception 'game_unavailable'; end if;
  update public.player_identities set access_token_digest = new_access_token_digest, access_token_rotated_at = now()
    where id = player.id;
  update public.player_devices set revoked_at = now() where player_devices.player_id = player.id and revoked_at is null;
  insert into public.player_devices(player_id, installation_id, name)
  values (player.id, target_installation_id, left(device_name, 120))
  on conflict on constraint player_devices_player_id_installation_id_key do update set
    name = excluded.name, revoked_at = null, last_seen_at = now();
  update public.recovery_tokens set used_at = now() where id = recovery.id;
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (game.id, player.id, 'player', 'recovery.redeemed', 'player_identity', player.id);
  return query select player.id, game.id, game.recipient_name;
end $$;

commit;
