begin;

update public.locations
  set dwell_seconds = 0,
      max_accuracy_meters = 250,
      radius_meters = greatest(radius_meters, 120);

create or replace function public.authorize_progress(
  raw_access_token text,
  target_installation_id uuid,
  content_kind text,
  content_id uuid,
  sample_latitude double precision,
  sample_longitude double precision,
  horizontal_accuracy double precision,
  dwell_started_at timestamptz,
  request_id uuid,
  fallback_code text default null
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare player public.player_identities%rowtype;
declare location public.locations%rowtype;
declare reward integer;
declare reward_kind public.reward_source;
declare distance_m double precision;
declare was_inserted boolean := false;
declare finale_inserted boolean := false;
declare affected_rows integer := 0;
declare bypass_location boolean := false;
declare game_row public.games%rowtype;
declare message_row public.friend_messages%rowtype;
declare dwell_at timestamptz := dwell_started_at;
declare allowed_m double precision;
begin
  select p.* into player from public.player_identities p
  join public.player_devices d on d.player_id = p.id
  where p.access_token_digest = extensions.digest(raw_access_token, 'sha256')
    and d.installation_id = target_installation_id and d.revoked_at is null;
  if not found then raise exception 'unauthorized' using errcode = 'P0001'; end if;

  select * into game_row from public.games where id = player.game_id and state = 'published';
  if not found then raise exception 'game_unavailable' using errcode = 'P0001'; end if;
  if game_row.launch_at is not null and game_row.launch_at > now() then
    raise exception 'not_launched' using errcode = 'P0001';
  end if;

  if (select count(*) from public.audit_events a where a.actor_id = player.id and a.action = 'progress.attempt' and a.created_at > now() - interval '1 minute') >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  if content_kind = 'character' then
    reward_kind := 'capture';
    select l.* into location from public.characters c
      join public.locations l on l.id = c.location_id
      where c.id = content_id and c.game_id = player.game_id and c.state = 'published' and l.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    select c.xp_value into reward from public.characters c where c.id = content_id;
  elsif content_kind = 'message' then
    reward_kind := 'message';
    select m.* into message_row from public.friend_messages m
      where m.id = content_id and m.game_id = player.game_id and m.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    reward := message_row.xp_value;
    if message_row.visibility = 'immediate' or message_row.location_id is null then
      bypass_location := true;
    else
      select l.* into location from public.locations l
        where l.id = message_row.location_id and l.state = 'published';
      if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    end if;
  elsif content_kind = 'landmark' then
    reward_kind := 'landmark';
    select l.* into location from public.landmarks x
      join public.locations l on l.id = x.location_id
      where x.id = content_id and x.game_id = player.game_id and x.state = 'published' and l.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    select x.xp_value into reward from public.landmarks x where x.id = content_id;
  else
    raise exception 'invalid_content_kind' using errcode = 'P0001';
  end if;

  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (player.game_id, player.id, 'player', 'progress.attempt', content_kind, content_id);

  if not bypass_location and (
    fallback_code is null
    or location.fallback_code_digest is null
    or extensions.digest(lower(trim(fallback_code)), 'sha256') <> location.fallback_code_digest
  ) then
    if sample_latitude is null or sample_longitude is null then
      raise exception 'location_required' using errcode = 'P0001';
    end if;
    if horizontal_accuracy is null or horizontal_accuracy <= 0 or horizontal_accuracy > location.max_accuracy_meters then
      raise exception 'location_inaccurate' using errcode = 'P0001';
    end if;
    if location.dwell_seconds > 0 then
      if dwell_at is not null and dwell_at > now() and dwell_at <= now() + interval '2 minutes' then
        dwell_at := now();
      end if;
      if dwell_at is null or dwell_at > now() or now() - dwell_at < make_interval(secs => location.dwell_seconds) then
        raise exception 'dwell_required' using errcode = 'P0001';
      end if;
    end if;
    distance_m := 6371000 * 2 * asin(sqrt(
      power(sin(radians(sample_latitude - location.latitude) / 2), 2) +
      cos(radians(location.latitude)) * cos(radians(sample_latitude)) *
      power(sin(radians(sample_longitude - location.longitude) / 2), 2)
    ));
    allowed_m := location.radius_meters + least(greatest(coalesce(horizontal_accuracy, 0), 0), 100);
    if distance_m > allowed_m then
      raise exception 'outside_radius' using errcode = 'P0001';
    end if;
  end if;

  if content_kind = 'character' then
    insert into public.captures(player_id, character_id, idempotency_key)
    values (player.id, content_id, request_id) on conflict do nothing;
  elsif content_kind = 'message' then
    insert into public.message_unlocks(player_id, message_id, idempotency_key)
    values (player.id, content_id, request_id) on conflict do nothing;
  else
    insert into public.landmark_visits(player_id, landmark_id, idempotency_key)
    values (player.id, content_id, request_id) on conflict do nothing;
  end if;
  get diagnostics affected_rows = row_count;
  was_inserted := affected_rows = 1;

  if was_inserted then
    perform public.apply_reward(player.id, reward_kind, content_id, reward);
  end if;

  if public.finale_is_eligible(player.id) then
    insert into public.finale_unlocks(player_id, idempotency_key)
    values (player.id, request_id) on conflict do nothing;
    get diagnostics affected_rows = row_count;
    finale_inserted := affected_rows = 1;
    if finale_inserted then
      perform public.apply_reward(player.id, 'finale', game_row.id, game_row.finale_xp);
    end if;
  end if;

  return public.player_bootstrap(raw_access_token, target_installation_id);
end $$;

commit;
