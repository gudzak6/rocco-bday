begin;

create function public.create_player_recovery(target_game_id uuid, validity interval default interval '24 hours')
returns text language plpgsql security definer set search_path = ''
as $$
declare recovered_player_id uuid;
declare raw_token text;
begin
  if not public.owns_game(target_game_id) then raise exception 'forbidden'; end if;
  if validity <= interval '0 seconds' or validity > interval '7 days' then raise exception 'invalid_expiry'; end if;
  select id into recovered_player_id from public.player_identities where game_id = target_game_id;
  if not found then raise exception 'player_not_redeemed'; end if;
  update public.recovery_tokens set revoked_at = now()
    where player_id = recovered_player_id and used_at is null and revoked_at is null;
  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.recovery_tokens(player_id, token_digest, expires_at, created_by)
  values (recovered_player_id, extensions.digest(raw_token, 'sha256'), now() + validity, auth.uid());
  return raw_token;
end $$;
revoke all on function public.create_player_recovery(uuid, interval) from public, anon;
grant execute on function public.create_player_recovery(uuid, interval) to authenticated;

create function public.redeem_player_recovery(
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
  update public.player_devices set revoked_at = now() where player_id = player.id and revoked_at is null;
  insert into public.player_devices(player_id, installation_id, name)
  values (player.id, target_installation_id, left(device_name, 120))
  on conflict (player_id, installation_id) do update set name = excluded.name, revoked_at = null, last_seen_at = now();
  update public.recovery_tokens set used_at = now() where id = recovery.id;
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (game.id, player.id, 'player', 'recovery.redeemed', 'player_identity', player.id);
  return query select player.id, game.id, game.recipient_name;
end $$;
revoke all on function public.redeem_player_recovery(bytea, bytea, uuid, text) from public, anon, authenticated;
grant execute on function public.redeem_player_recovery(bytea, bytea, uuid, text) to service_role;

commit;
