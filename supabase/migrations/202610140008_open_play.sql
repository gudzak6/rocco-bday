begin;

alter table public.games
  add column if not exists open_play boolean not null default true;

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
  on conflict (game_id) do update set
    access_token_digest = excluded.access_token_digest,
    access_token_rotated_at = now()
  returning * into player;

  insert into public.player_devices(player_id, installation_id, name)
  values (player.id, target_installation_id, left(device_name, 120))
  on conflict (player_id, installation_id) do update set
    name = excluded.name, revoked_at = null, last_seen_at = now();

  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (game.id, player.id, 'player', 'open_play.joined', 'player_identity', player.id);

  return query select player.id, game.id, game.recipient_name;
end $$;
revoke all on function public.join_open_game(bytea, uuid, text) from public, anon, authenticated;
grant execute on function public.join_open_game(bytea, uuid, text) to service_role;

commit;
