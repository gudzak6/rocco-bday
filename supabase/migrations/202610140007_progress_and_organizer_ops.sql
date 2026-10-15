begin;

-- Captures were broken: content_kind 'character' cannot be cast to reward_source
-- ('capture','message','landmark','finale'). Immediate notes must skip GPS.
-- Published characters must be tied to a location. Organizers need fallback-code
-- and archive helpers that do not hard-delete live progress sources.

create or replace function public.player_bootstrap(raw_access_token text, target_installation_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare player public.player_identities%rowtype;
declare game public.games%rowtype;
declare device public.player_devices%rowtype;
begin
  select * into player from public.player_identities
  where access_token_digest = extensions.digest(raw_access_token, 'sha256');
  if not found then raise exception 'unauthorized' using errcode = 'P0001'; end if;
  select * into device from public.player_devices
  where player_id = player.id and installation_id = target_installation_id and revoked_at is null;
  if not found then raise exception 'device_revoked' using errcode = 'P0001'; end if;
  update public.player_devices set last_seen_at = now() where id = device.id;
  select * into game from public.games where id = player.game_id and state = 'published';
  if not found then raise exception 'game_unavailable' using errcode = 'P0001'; end if;

  return jsonb_build_object(
    'game', jsonb_build_object(
      'id', game.id, 'title', game.title, 'recipientName', game.recipient_name,
      'introMessage', game.intro_message, 'coverArtPath', game.cover_art_path,
      'launchAt', game.launch_at, 'xp', player.xp, 'avatarStyle', player.avatar_style
    ),
    'locations', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'title', l.title, 'latitude', l.latitude, 'longitude', l.longitude,
      'radiusMeters', l.radius_meters, 'maxAccuracyMeters', l.max_accuracy_meters,
      'dwellSeconds', l.dwell_seconds, 'hint', l.hint, 'sortOrder', l.sort_order,
      'hasFallback', l.fallback_code_digest is not null
    ) order by l.sort_order) from public.locations l where l.game_id = game.id and l.state = 'published'), '[]'::jsonb),
    'characters', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'locationId', c.location_id, 'name', c.name, 'category', c.category,
      'rarity', c.rarity, 'required', c.required, 'xpValue', c.xp_value,
      'sortOrder', c.sort_order, 'captured', x.id is not null,
      'description', case when x.id is not null then c.description else null end,
      'personality', case when x.id is not null then c.personality else null end,
      'specialAbility', case when x.id is not null then c.special_ability else null end,
      'artworkPath', case when x.id is not null then c.artwork_path else null end
    ) order by c.sort_order)
    from public.characters c left join public.captures x on x.character_id = c.id and x.player_id = player.id
    where c.game_id = game.id and c.state = 'published'), '[]'::jsonb),
    'messagePins', coalesce((select jsonb_agg(jsonb_build_object(
      'id', m.id, 'locationId', m.location_id, 'title', m.title, 'senderName',
      case when u.id is not null then m.sender_name else null end,
      'visibility', m.visibility, 'required', m.required, 'unlocked', u.id is not null
    ) order by m.sort_order)
    from public.friend_messages m left join public.message_unlocks u on u.message_id = m.id and u.player_id = player.id
    where m.game_id = game.id and m.state = 'published'), '[]'::jsonb),
    'unlockedMessages', coalesce((select jsonb_agg(jsonb_build_object(
      'id', m.id, 'title', m.title, 'senderName', m.sender_name, 'body', m.body,
      'locationId', m.location_id, 'unlockedAt', u.unlocked_at,
      'media', coalesce((select jsonb_agg(jsonb_build_object('id', mm.id, 'kind', mm.kind, 'path', mm.storage_path, 'mimeType', mm.mime_type, 'durationSeconds', mm.duration_seconds) order by mm.sort_order)
        from public.message_media mm where mm.message_id = m.id), '[]'::jsonb)
    ) order by u.unlocked_at desc)
    from public.friend_messages m
    join public.message_unlocks u on u.message_id = m.id and u.player_id = player.id
    where m.game_id = game.id), '[]'::jsonb),
    'landmarks', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'locationId', l.location_id, 'title', l.title, 'description', l.description,
      'story', l.story, 'imagePath', l.image_path, 'required', l.required,
      'visited', v.id is not null, 'sortOrder', l.sort_order
    ) order by l.sort_order)
    from public.landmarks l left join public.landmark_visits v on v.landmark_id = l.id and v.player_id = player.id
    where l.game_id = game.id and l.state = 'published'), '[]'::jsonb),
    'finale', case when exists(select 1 from public.finale_unlocks f where f.player_id = player.id)
      then jsonb_build_object('unlocked', true, 'title', game.finale_title, 'letter', game.finale_letter,
        'mediaPath', game.finale_media_path, 'destination', game.finale_destination)
      else jsonb_build_object('unlocked', false) end
  );
end $$;

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
    if dwell_started_at is null or dwell_started_at > now() or now() - dwell_started_at < make_interval(secs => location.dwell_seconds) then
      raise exception 'dwell_required' using errcode = 'P0001';
    end if;
    distance_m := 6371000 * 2 * asin(sqrt(
      power(sin(radians(sample_latitude - location.latitude) / 2), 2) +
      cos(radians(location.latitude)) * cos(radians(sample_latitude)) *
      power(sin(radians(sample_longitude - location.longitude) / 2), 2)
    ));
    if distance_m > location.radius_meters then
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

create or replace function public.publish_game(target_game_id uuid) returns void
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
  if exists(select 1 from public.characters where game_id = target_game_id and state <> 'archived' and location_id is null) then
    raise exception 'character_location_required';
  end if;
  if exists(
    select 1 from public.friend_messages
    where game_id = target_game_id and state <> 'archived'
      and visibility = 'location_locked' and location_id is null
  ) then
    raise exception 'message_location_required';
  end if;
  update public.locations set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.characters set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.friend_messages set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.landmarks set state = 'published' where game_id = target_game_id and state = 'draft';
  update public.games set state = 'published', published_at = coalesce(published_at, now()) where id = target_game_id;
  insert into public.audit_events(game_id, actor_id, actor_type, action)
  values (target_game_id, auth.uid(), 'organizer', 'game.published');
end $$;

create or replace function public.create_scoped_invitation(
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
  if invitation_type = 'recovery' then raise exception 'use_recovery_rpc'; end if;
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

create or replace function public.set_location_fallback(target_location_id uuid, raw_code text)
returns void language plpgsql security definer set search_path = ''
as $$
declare loc public.locations%rowtype;
begin
  select * into loc from public.locations where id = target_location_id;
  if not found or not public.owns_game(loc.game_id) then raise exception 'forbidden'; end if;
  if char_length(trim(raw_code)) < 6 or char_length(trim(raw_code)) > 32 then raise exception 'invalid_code'; end if;
  update public.locations
    set fallback_code_digest = extensions.digest(lower(trim(raw_code)), 'sha256')
    where id = target_location_id;
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (loc.game_id, auth.uid(), 'organizer', 'location.fallback_set', 'location', loc.id);
end $$;
revoke all on function public.set_location_fallback(uuid, text) from public, anon;
grant execute on function public.set_location_fallback(uuid, text) to authenticated;

create or replace function public.archive_game_content(
  target_game_id uuid,
  target_table text,
  target_id uuid,
  confirmation text
) returns void language plpgsql security definer set search_path = ''
as $$
declare current_state public.content_status;
begin
  if not public.owns_game(target_game_id) then raise exception 'forbidden'; end if;
  if target_table not in ('locations', 'characters', 'friend_messages', 'landmarks') then
    raise exception 'invalid_table';
  end if;
  execute format('select state from public.%I where id = $1 and game_id = $2', target_table)
    into current_state using target_id, target_game_id;
  if current_state is null then raise exception 'content_unavailable'; end if;
  if current_state = 'published' and confirmation is distinct from 'ARCHIVE' then
    raise exception 'confirmation_required';
  end if;
  execute format('update public.%I set state = ''archived'' where id = $1 and game_id = $2', target_table)
    using target_id, target_game_id;
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (target_game_id, auth.uid(), 'organizer', 'content.archived', target_table, target_id);
end $$;
revoke all on function public.archive_game_content(uuid, text, uuid, text) from public, anon;
grant execute on function public.archive_game_content(uuid, text, uuid, text) to authenticated;

create or replace function public.update_player_avatar(
  raw_access_token text,
  target_installation_id uuid,
  style jsonb
) returns void language plpgsql security definer set search_path = ''
as $$
declare player public.player_identities%rowtype;
begin
  select p.* into player from public.player_identities p
  join public.player_devices d on d.player_id = p.id
  where p.access_token_digest = extensions.digest(raw_access_token, 'sha256')
    and d.installation_id = target_installation_id and d.revoked_at is null;
  if not found then raise exception 'unauthorized' using errcode = 'P0001'; end if;
  if jsonb_typeof(style) is distinct from 'object' then raise exception 'invalid_avatar'; end if;
  update public.player_identities set avatar_style = style where id = player.id;
end $$;
revoke all on function public.update_player_avatar(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.update_player_avatar(text, uuid, jsonb) to service_role;

commit;
