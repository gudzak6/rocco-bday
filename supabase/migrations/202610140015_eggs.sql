begin;

create type public.egg_status as enum ('available', 'incubating', 'ready', 'hatched');

create table public.egg_types (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  type_key text not null check (char_length(type_key) between 1 and 40),
  title text not null check (char_length(title) between 1 and 80),
  required_meters double precision not null check (required_meters between 100 and 200000),
  xp_value integer not null default 50 check (xp_value between 0 and 10000),
  artwork_style text not null default 'sky' check (artwork_style in ('sky', 'gold')),
  rarity_label text not null default 'Common or rare',
  allowed_rarities text[] not null default array['common', 'rare']::text[],
  exclude_duplicates boolean not null default true,
  duplicate_xp integer not null default 15 check (duplicate_xp >= 0),
  artwork_path text,
  state public.content_status not null default 'published',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, type_key)
);

create table public.egg_type_rewards (
  id uuid primary key default gen_random_uuid(),
  egg_type_id uuid not null references public.egg_types(id) on delete cascade,
  character_id uuid not null references public.characters(id) on delete cascade,
  weight double precision not null default 1 check (weight > 0),
  unique (egg_type_id, character_id)
);

create table public.player_eggs (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  egg_type_id uuid not null references public.egg_types(id) on delete restrict,
  status public.egg_status not null default 'available',
  meters_walked double precision not null default 0 check (meters_walked >= 0),
  started_at timestamptz,
  ready_at timestamptz,
  hatched_at timestamptz,
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index player_eggs_player_idx on public.player_eggs(player_id, status);

create table public.egg_incubations (
  id uuid primary key default gen_random_uuid(),
  player_egg_id uuid not null unique references public.player_eggs(id) on delete cascade,
  player_id uuid not null references public.player_identities(id) on delete cascade,
  meters_walked double precision not null default 0 check (meters_walked >= 0),
  last_report_at timestamptz,
  paused boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.egg_hatch_rewards (
  id uuid primary key default gen_random_uuid(),
  player_egg_id uuid not null unique references public.player_eggs(id) on delete cascade,
  player_id uuid not null references public.player_identities(id) on delete cascade,
  character_id uuid references public.characters(id) on delete set null,
  xp_awarded integer not null default 0,
  was_duplicate boolean not null default false,
  idempotency_key uuid not null unique,
  created_at timestamptz not null default now()
);

alter table public.egg_types enable row level security;
alter table public.egg_type_rewards enable row level security;
alter table public.player_eggs enable row level security;
alter table public.egg_incubations enable row level security;
alter table public.egg_hatch_rewards enable row level security;

create policy organizer_egg_types on public.egg_types for all to authenticated
using (public.owns_game(game_id)) with check (public.owns_game(game_id));
create policy organizer_egg_rewards on public.egg_type_rewards for all to authenticated
using (exists(select 1 from public.egg_types t where t.id = egg_type_id and public.owns_game(t.game_id)))
with check (exists(select 1 from public.egg_types t where t.id = egg_type_id and public.owns_game(t.game_id)));
create policy organizer_player_eggs on public.player_eggs for all to authenticated
using (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)))
with check (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)));
create policy organizer_egg_incubations on public.egg_incubations for select to authenticated
using (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)));
create policy organizer_egg_hatches on public.egg_hatch_rewards for select to authenticated
using (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)));

create or replace function public.ensure_default_egg_types(target_game_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.egg_types (
    game_id, type_key, title, required_meters, xp_value, artwork_style, rarity_label,
    allowed_rarities, exclude_duplicates, duplicate_xp, sort_order
  ) values
    (
      target_game_id, 'one-mile', '1-Mile Egg',
      1609.344, 50, 'sky', 'Common or rare', array['common','rare']::text[], true, 15, 0
    ),
    (
      target_game_id, 'ten-mile', '10-Mile Egg',
      16093.44, 200, 'gold', 'Rare or legendary', array['rare','legendary']::text[], true, 40, 1
    )
  on conflict (game_id, type_key) do update set
    required_meters = excluded.required_meters,
    xp_value = excluded.xp_value,
    artwork_style = excluded.artwork_style,
    rarity_label = excluded.rarity_label,
    allowed_rarities = excluded.allowed_rarities,
    updated_at = now();
end $$;

do $$
declare game_row public.games%rowtype;
begin
  for game_row in select * from public.games loop
    perform public.ensure_default_egg_types(game_row.id);
    insert into public.characters (game_id, name, category, rarity, description, personality, special_ability, required, xp_value, sort_order, state)
    select game_row.id, seed.name, seed.category::public.character_category, seed.rarity::public.character_rarity,
           seed.description, seed.personality, seed.ability, false, seed.xp, seed.sort, 'published'
    from (values
      ('Balloon Buddy', 'friend', 'rare', 'A helium-hearted friend who shows up for every birthday walk.', 'Buoyant and loyal', 'Lifts the mood', 80, 80),
      ('Snack Sprite', 'food', 'common', 'A crumb-sized celebration that smells like the good bakery.', 'Always hungry', 'Shares the last bite', 40, 81),
      ('Joke Spark', 'inside_joke', 'rare', 'Hatches only for people who already know the punchline.', 'Wry', 'Callback humor', 80, 82),
      ('Confetti Spark', 'legendary', 'legendary', 'A rare burst of birthday light earned one long walk at a time.', 'Dazzling', 'Turns sidewalks into parades', 200, 83),
      ('Birthday Crown', 'legendary', 'legendary', 'An exclusive hatch for the person the day is really about.', 'Regal and warm', 'Makes any block feel like a procession', 220, 84),
      ('Golden Party Pal', 'friend', 'rare', 'A 10-mile companion with a pocket full of surprises.', 'Generous', 'Saves the best gift for last', 120, 85)
    ) as seed(name, category, rarity, description, personality, ability, xp, sort)
    where not exists (
      select 1 from public.characters c where c.game_id = game_row.id and c.name = seed.name
    );
  end loop;
end $$;

create or replace function public.ensure_starter_eggs(target_player_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare player public.player_identities%rowtype;
begin
  select * into player from public.player_identities where id = target_player_id;
  if not found then return; end if;
  perform public.ensure_default_egg_types(player.game_id);
  insert into public.player_eggs (player_id, egg_type_id)
  select player.id, t.id
  from public.egg_types t
  where t.game_id = player.game_id and t.state = 'published'
    and not exists (
      select 1 from public.player_eggs e
      where e.player_id = player.id and e.egg_type_id = t.id
    );
end $$;

create or replace function public.grant_player_egg(target_game_id uuid, target_player_id uuid, target_egg_type_id uuid, test_grant boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if not public.owns_game(target_game_id) then raise exception 'forbidden'; end if;
  insert into public.player_eggs (player_id, egg_type_id, is_test)
  select target_player_id, target_egg_type_id, test_grant
  from public.player_identities p
  join public.egg_types t on t.id = target_egg_type_id and t.game_id = target_game_id
  where p.id = target_player_id and p.game_id = target_game_id
  returning id into new_id;
  if new_id is null then raise exception 'grant_failed'; end if;
  return new_id;
end $$;
grant execute on function public.grant_player_egg(uuid, uuid, uuid, boolean) to authenticated;

create or replace function public.reset_test_eggs(target_game_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare affected integer;
begin
  if not public.owns_game(target_game_id) then raise exception 'forbidden'; end if;
  update public.player_eggs e
  set status = 'available', meters_walked = 0, started_at = null, ready_at = null, hatched_at = null, updated_at = now()
  from public.player_identities p
  where e.player_id = p.id and p.game_id = target_game_id and e.is_test = true;
  get diagnostics affected = row_count;
  delete from public.egg_hatch_rewards h
  using public.player_eggs e, public.player_identities p
  where h.player_egg_id = e.id and e.player_id = p.id and p.game_id = target_game_id and e.is_test = true;
  delete from public.egg_incubations i
  using public.player_eggs e, public.player_identities p
  where i.player_egg_id = e.id and e.player_id = p.id and p.game_id = target_game_id and e.is_test = true;
  return affected;
end $$;
grant execute on function public.reset_test_eggs(uuid) to authenticated;

create or replace function public.player_snapshot(raw_access_token text, target_installation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
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

  insert into public.message_unlocks(player_id, message_id, idempotency_key)
  select player.id, m.id, gen_random_uuid()
  from public.friend_messages m
  where m.game_id = player.game_id and m.state = 'published'
    and (m.visibility = 'immediate' or m.unlock_type = 'immediate')
  on conflict do nothing;

  perform public.evaluate_birthday_notes(player.id);
  perform public.ensure_starter_eggs(player.id);

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
      'id', m.id, 'locationId', m.location_id, 'title', m.title,
      'senderName', case when u.id is not null or m.reveal_sender_when_locked then m.sender_name else null end,
      'visibility', m.visibility, 'required', m.required, 'unlocked', u.id is not null,
      'unlockType', m.unlock_type, 'unlockRule', m.unlock_rule,
      'characterId', m.character_id, 'passportStampKey', m.passport_stamp_key,
      'lockedHint', m.locked_hint, 'revealSender', m.reveal_sender_when_locked,
      'hasPhoto', exists(select 1 from public.message_media mm where mm.message_id = m.id and mm.kind = 'image'),
      'hasAudio', exists(select 1 from public.message_media mm where mm.message_id = m.id and mm.kind = 'audio')
    ) order by m.sort_order)
    from public.friend_messages m left join public.message_unlocks u on u.message_id = m.id and u.player_id = player.id
    where m.game_id = game.id and m.state = 'published'), '[]'::jsonb),
    'unlockedMessages', coalesce((select jsonb_agg(jsonb_build_object(
      'id', m.id, 'title', m.title, 'senderName', m.sender_name, 'body', m.body,
      'locationId', m.location_id, 'unlockedAt', u.unlocked_at, 'characterId', m.character_id,
      'passportStampKey', m.passport_stamp_key, 'senderPhotoPath', m.sender_photo_path,
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
    'passportStamps', coalesce((select jsonb_agg(s.stamp_key order by s.earned_at) from public.player_stamps s where s.player_id = player.id), '[]'::jsonb),
    'finale', case when exists(select 1 from public.finale_unlocks f where f.player_id = player.id)
      then jsonb_build_object('unlocked', true, 'title', game.finale_title, 'letter', game.finale_letter,
        'mediaPath', game.finale_media_path, 'destination', game.finale_destination)
      else jsonb_build_object('unlocked', false) end,
    'eggTypes', coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'key', t.type_key, 'title', t.title, 'requiredMeters', t.required_meters,
      'xpValue', t.xp_value, 'artworkStyle', t.artwork_style, 'rarityLabel', t.rarity_label,
      'allowedRarities', to_jsonb(t.allowed_rarities), 'excludeDuplicates', t.exclude_duplicates,
      'duplicateXp', t.duplicate_xp, 'artworkPath', t.artwork_path,
      'rewardCharacterIds', coalesce((select jsonb_agg(r.character_id) from public.egg_type_rewards r where r.egg_type_id = t.id), '[]'::jsonb),
      'rewardWeights', coalesce((select jsonb_object_agg(r.character_id::text, r.weight) from public.egg_type_rewards r where r.egg_type_id = t.id), '{}'::jsonb)
    ) order by t.sort_order) from public.egg_types t where t.game_id = game.id and t.state = 'published'), '[]'::jsonb),
    'playerEggs', coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'eggTypeId', e.egg_type_id, 'typeKey', t.type_key, 'status', e.status,
      'metersWalked', e.meters_walked, 'requiredMeters', t.required_meters,
      'startedAt', e.started_at, 'readyAt', e.ready_at, 'hatchedAt', e.hatched_at,
      'rewardCharacterId', h.character_id, 'isTest', e.is_test
    ) order by e.created_at)
    from public.player_eggs e
    join public.egg_types t on t.id = e.egg_type_id
    left join public.egg_hatch_rewards h on h.player_egg_id = e.id
    where e.player_id = player.id), '[]'::jsonb)
  );
end $$;

create or replace function public.hatch_egg(
  raw_access_token text,
  target_installation_id uuid,
  target_egg_id uuid,
  request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare player public.player_identities%rowtype;
declare egg public.player_eggs%rowtype;
declare egg_type public.egg_types%rowtype;
declare existing public.egg_hatch_rewards%rowtype;
declare chosen uuid;
declare already boolean := false;
declare xp integer;
begin
  select * into player from public.player_identities
  where access_token_digest = extensions.digest(raw_access_token, 'sha256');
  if not found then raise exception 'unauthorized' using errcode = 'P0001'; end if;
  if not exists (
    select 1 from public.player_devices d
    where d.player_id = player.id and d.installation_id = target_installation_id and d.revoked_at is null
  ) then raise exception 'device_revoked' using errcode = 'P0001'; end if;

  select * into existing from public.egg_hatch_rewards
  where player_egg_id = target_egg_id or idempotency_key = request_id;
  if found then
    return public.player_snapshot(raw_access_token, target_installation_id);
  end if;

  select * into egg from public.player_eggs where id = target_egg_id and player_id = player.id;
  if not found then raise exception 'egg_missing' using errcode = 'P0001'; end if;
  select * into egg_type from public.egg_types where id = egg.egg_type_id;
  if egg.meters_walked + 0.5 < egg_type.required_meters and egg.status <> 'ready' then
    raise exception 'egg_not_ready' using errcode = 'P0001';
  end if;

  select c.id, exists(select 1 from public.captures x where x.player_id = player.id and x.character_id = c.id)
  into chosen, already
  from public.characters c
  where c.game_id = player.game_id and c.state = 'published'
    and c.rarity::text = any(egg_type.allowed_rarities)
    and (
      not exists (select 1 from public.egg_type_rewards r where r.egg_type_id = egg_type.id)
      or exists (select 1 from public.egg_type_rewards r where r.egg_type_id = egg_type.id and r.character_id = c.id)
    )
    and (
      egg_type.exclude_duplicates = false
      or not exists (select 1 from public.captures x where x.player_id = player.id and x.character_id = c.id)
    )
  order by random()
  limit 1;

  if chosen is null then
    xp := egg_type.duplicate_xp;
    insert into public.egg_hatch_rewards(player_egg_id, player_id, character_id, xp_awarded, was_duplicate, idempotency_key)
    values (egg.id, player.id, null, xp, true, request_id)
    on conflict do nothing;
  else
    xp := egg_type.xp_value;
    insert into public.egg_hatch_rewards(player_egg_id, player_id, character_id, xp_awarded, was_duplicate, idempotency_key)
    values (egg.id, player.id, chosen, xp, already, request_id)
    on conflict do nothing;
    insert into public.captures(player_id, character_id, idempotency_key)
    values (player.id, chosen, request_id)
    on conflict do nothing;
    perform public.apply_reward(player.id, 'capture', chosen, xp);
  end if;

  if chosen is null then
    perform public.apply_reward(player.id, 'capture', egg.id, xp);
  end if;

  update public.player_eggs
  set status = 'hatched', hatched_at = coalesce(hatched_at, now()), meters_walked = egg_type.required_meters, updated_at = now()
  where id = egg.id;
  delete from public.egg_incubations where player_egg_id = egg.id;

  return public.player_snapshot(raw_access_token, target_installation_id);
end $$;
revoke all on function public.hatch_egg(text, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.hatch_egg(text, uuid, uuid, uuid) to service_role;

commit;
