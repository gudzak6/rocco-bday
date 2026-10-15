begin;

create function public.digest_token(raw_token text) returns bytea
language sql immutable set search_path = ''
as $$ select extensions.digest(raw_token, 'sha256') $$;
revoke all on function public.digest_token(text) from public, anon, authenticated;
grant execute on function public.digest_token(text) to service_role;

create function public.redeem_player_invitation(
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
  on conflict (game_id) do update set
    access_token_digest = excluded.access_token_digest,
    access_token_rotated_at = now()
  returning * into player;

  insert into public.player_devices(player_id, installation_id, name)
  values (player.id, target_installation_id, left(device_name, 120))
  on conflict (player_id, installation_id) do update set
    name = excluded.name, revoked_at = null, last_seen_at = now();

  update public.invitations set use_count = use_count + 1 where id = invite.id;
  insert into public.audit_events(game_id, actor_id, actor_type, action, target_type, target_id)
  values (game.id, player.id, 'player', 'invitation.redeemed', 'player_identity', player.id);

  return query select player.id, game.id, game.recipient_name;
end $$;
revoke all on function public.redeem_player_invitation(bytea, bytea, uuid, text) from public, anon, authenticated;
grant execute on function public.redeem_player_invitation(bytea, bytea, uuid, text) to service_role;

create function public.player_bootstrap(raw_access_token text, target_installation_id uuid)
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
      'launchAt', game.launch_at, 'xp', player.xp
    ),
    'locations', coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'title', l.title, 'latitude', l.latitude, 'longitude', l.longitude,
      'radiusMeters', l.radius_meters, 'hint', l.hint, 'sortOrder', l.sort_order
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
    from public.friend_messages m join public.message_unlocks u on u.message_id = m.id and u.player_id = player.id), '[]'::jsonb),
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
revoke all on function public.player_bootstrap(text, uuid) from public, anon, authenticated;
grant execute on function public.player_bootstrap(text, uuid) to service_role;

create function public.authorize_progress(
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
declare distance_m double precision;
declare was_inserted boolean := false;
declare finale_inserted boolean := false;
declare affected_rows integer := 0;
declare bypass_location boolean := false;
declare game_row public.games%rowtype;
begin
  select p.* into player from public.player_identities p
  join public.player_devices d on d.player_id = p.id
  where p.access_token_digest = extensions.digest(raw_access_token, 'sha256')
    and d.installation_id = target_installation_id and d.revoked_at is null;
  if not found then raise exception 'unauthorized' using errcode = 'P0001'; end if;

  if (select count(*) from public.audit_events a where a.actor_id = player.id and a.action = 'progress.attempt' and a.created_at > now() - interval '1 minute') >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  if content_kind = 'character' then
    select l.* into location from public.characters c
      join public.locations l on l.id = c.location_id
      where c.id = content_id and c.game_id = player.game_id and c.state = 'published' and l.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    select c.xp_value into reward from public.characters c where c.id = content_id;
  elsif content_kind = 'message' then
    select m.xp_value, m.location_id is null into reward, bypass_location from public.friend_messages m
      where m.id = content_id and m.game_id = player.game_id and m.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    if not bypass_location then
      select l.* into location from public.friend_messages m
        join public.locations l on l.id = m.location_id
        where m.id = content_id and l.state = 'published';
      if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    end if;
  elsif content_kind = 'landmark' then
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
    if horizontal_accuracy <= 0 or horizontal_accuracy > location.max_accuracy_meters then
      raise exception 'location_inaccurate' using errcode = 'P0001';
    end if;
    if dwell_started_at > now() or now() - dwell_started_at < make_interval(secs => location.dwell_seconds) then
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
    perform public.apply_reward(player.id, content_kind::public.reward_source, content_id, reward);
  end if;

  if public.finale_is_eligible(player.id) then
    select * into game_row from public.games where id = player.game_id;
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
revoke all on function public.authorize_progress(text, uuid, text, uuid, double precision, double precision, double precision, timestamptz, uuid, text) from public, anon, authenticated;
grant execute on function public.authorize_progress(text, uuid, text, uuid, double precision, double precision, double precision, timestamptz, uuid, text) to service_role;

commit;
