begin;

alter table public.friend_messages
  add column if not exists unlock_type text not null default 'location'
    check (unlock_type in ('immediate', 'location', 'character', 'passport', 'composite')),
  add column if not exists unlock_rule text not null default 'all'
    check (unlock_rule in ('all', 'any')),
  add column if not exists character_id uuid references public.characters(id) on delete set null,
  add column if not exists passport_stamp_key text check (char_length(passport_stamp_key) <= 80),
  add column if not exists sender_photo_path text,
  add column if not exists locked_hint text check (char_length(locked_hint) <= 240),
  add column if not exists reveal_sender_when_locked boolean not null default false;

do $$
declare constraint_name text;
begin
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'public.friend_messages'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%location_id is not null%';
  if constraint_name is not null then
    execute format('alter table public.friend_messages drop constraint %I', constraint_name);
  end if;
end $$;

update public.friend_messages
set unlock_type = case when visibility = 'immediate' or location_id is null then 'immediate' else 'location' end
where unlock_type = 'location' and visibility = 'immediate';

create table if not exists public.player_stamps (
  player_id uuid not null references public.player_identities(id) on delete cascade,
  stamp_key text not null check (char_length(stamp_key) between 1 and 80),
  earned_at timestamptz not null default now(),
  unique (player_id, stamp_key)
);

alter table public.player_stamps enable row level security;

drop policy if exists organizer_stamps on public.player_stamps;
create policy organizer_stamps on public.player_stamps for select to authenticated
using (exists(
  select 1 from public.player_identities p
  where p.id = player_id and public.owns_game(p.game_id)
));

create or replace function public.stamp_key_for_location(target_location_id uuid)
returns text language sql stable set search_path = '' as $$
  select case l.title
    when 'Grand Central Terminal' then 'grand-central'
    when 'Penn Station' then 'penn-station'
    when 'NYRR RUNCENTER' then 'runcenter'
    when 'Chip City Rockefeller' then 'chip-city-rockefeller'
    when 'Chip City Chelsea' then 'chip-city-chelsea'
    when 'Williamsburg' then 'williamsburg'
    when 'Upper East Side' then 'upper-east-side'
    else null
  end
  from public.locations l where l.id = target_location_id;
$$;

create or replace function public.evaluate_birthday_notes(target_player_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare note public.friend_messages%rowtype;
declare unlocked_count integer := 0;
declare affected_rows integer := 0;
declare location_ok boolean;
declare character_ok boolean;
declare stamp_ok boolean;
declare should_unlock boolean;
begin
  for note in
    select m.* from public.friend_messages m
    join public.player_identities p on p.game_id = m.game_id
    where p.id = target_player_id and m.state = 'published'
      and not exists (select 1 from public.message_unlocks u where u.player_id = target_player_id and u.message_id = m.id)
  loop
    location_ok := note.location_id is null or exists (
      select 1 from public.landmark_visits v
      join public.landmarks l on l.id = v.landmark_id
      where v.player_id = target_player_id and l.location_id = note.location_id
    ) or exists (
      select 1 from public.captures c
      join public.characters ch on ch.id = c.character_id
      where c.player_id = target_player_id and ch.location_id = note.location_id
    );
    character_ok := note.character_id is null or exists (
      select 1 from public.captures c where c.player_id = target_player_id and c.character_id = note.character_id
    );
    stamp_ok := note.passport_stamp_key is null or exists (
      select 1 from public.player_stamps s where s.player_id = target_player_id and s.stamp_key = note.passport_stamp_key
    );

    if note.unlock_type = 'immediate' or note.visibility = 'immediate' then
      should_unlock := true;
    elsif note.unlock_type = 'location' then
      should_unlock := location_ok;
    elsif note.unlock_type = 'character' then
      should_unlock := character_ok;
    elsif note.unlock_type = 'passport' then
      should_unlock := stamp_ok;
    else
      if note.unlock_rule = 'any' then
        should_unlock := (note.location_id is not null and location_ok)
          or (note.character_id is not null and character_ok)
          or (note.passport_stamp_key is not null and stamp_ok);
      else
        should_unlock := (note.location_id is null or location_ok)
          and (note.character_id is null or character_ok)
          and (note.passport_stamp_key is null or stamp_ok)
          and (note.location_id is not null or note.character_id is not null or note.passport_stamp_key is not null);
      end if;
    end if;

    if should_unlock then
      insert into public.message_unlocks(player_id, message_id, idempotency_key)
      values (target_player_id, note.id, gen_random_uuid())
      on conflict do nothing;
      get diagnostics affected_rows = row_count;
      if affected_rows = 1 then
        unlocked_count := unlocked_count + 1;
        perform public.apply_reward(target_player_id, 'message', note.id, note.xp_value);
      end if;
    end if;
  end loop;
  return unlocked_count;
end $$;

create or replace function public.grant_location_stamp(target_player_id uuid, target_location_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare key text;
begin
  key := public.stamp_key_for_location(target_location_id);
  if key is null then return; end if;
  insert into public.player_stamps(player_id, stamp_key) values (target_player_id, key)
  on conflict do nothing;
end $$;

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
declare dwell_at timestamptz := dwell_started_at;
declare allowed_m double precision;
declare stamp_loc uuid;
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
    stamp_loc := location.id;
  elsif content_kind = 'message' then
    reward_kind := 'message';
    select m.* into message_row from public.friend_messages m
      where m.id = content_id and m.game_id = player.game_id and m.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    reward := message_row.xp_value;
    if message_row.visibility = 'immediate' or message_row.unlock_type in ('immediate', 'character', 'passport') or message_row.location_id is null then
      bypass_location := true;
    else
      select l.* into location from public.locations l
        where l.id = message_row.location_id and l.state = 'published';
      if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    end if;
    if message_row.unlock_type = 'character' and message_row.character_id is not null
       and not exists (select 1 from public.captures c where c.player_id = player.id and c.character_id = message_row.character_id) then
      raise exception 'character_required' using errcode = 'P0001';
    end if;
    if message_row.unlock_type = 'passport' and message_row.passport_stamp_key is not null
       and not exists (select 1 from public.player_stamps s where s.player_id = player.id and s.stamp_key = message_row.passport_stamp_key) then
      raise exception 'stamp_required' using errcode = 'P0001';
    end if;
    if message_row.unlock_type = 'composite' then
      declare
        character_ready boolean := message_row.character_id is null or exists (
          select 1 from public.captures c where c.player_id = player.id and c.character_id = message_row.character_id
        );
        stamp_ready boolean := message_row.passport_stamp_key is null or exists (
          select 1 from public.player_stamps s where s.player_id = player.id and s.stamp_key = message_row.passport_stamp_key
        );
      begin
        if message_row.location_id is null or (message_row.unlock_rule = 'any' and (character_ready or stamp_ready)) then
          bypass_location := true;
        end if;
        if message_row.unlock_rule = 'any' then
          if not (
            (message_row.location_id is not null and not bypass_location)
            or character_ready
            or stamp_ready
          ) and message_row.location_id is null then
            raise exception 'prerequisites_required' using errcode = 'P0001';
          end if;
        elsif not character_ready or not stamp_ready then
          raise exception 'prerequisites_required' using errcode = 'P0001';
        end if;
      end;
    end if;
  elsif content_kind = 'landmark' then
    reward_kind := 'landmark';
    select l.* into location from public.landmarks x
      join public.locations l on l.id = x.location_id
      where x.id = content_id and x.game_id = player.game_id and x.state = 'published' and l.state = 'published';
    if not found then raise exception 'content_unavailable' using errcode = 'P0001'; end if;
    select x.xp_value into reward from public.landmarks x where x.id = content_id;
    stamp_loc := location.id;
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
    if horizontal_accuracy is null or horizontal_accuracy <= 0 or horizontal_accuracy > greatest(location.max_accuracy_meters, 250) then
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
  if stamp_loc is not null then
    perform public.grant_location_stamp(player.id, stamp_loc);
  end if;
  perform public.evaluate_birthday_notes(player.id);

  if public.finale_is_eligible(player.id) then
    insert into public.finale_unlocks(player_id, idempotency_key)
    values (player.id, request_id) on conflict do nothing;
    get diagnostics affected_rows = row_count;
    finale_inserted := affected_rows = 1;
    if finale_inserted then
      perform public.apply_reward(player.id, 'finale', game_row.id, game_row.finale_xp);
    end if;
  end if;

  return public.player_snapshot(raw_access_token, target_installation_id);
end $$;

update public.friend_messages m
set unlock_type = 'passport',
    passport_stamp_key = case m.title
      when 'Meet me under the clock' then 'grand-central'
      when 'This way. No, that way.' then 'penn-station'
      else m.passport_stamp_key
    end,
    locked_hint = case m.title
      when 'Meet me under the clock' then 'A commute note is waiting after the Grand Central stamp.'
      when 'This way. No, that way.' then 'A funny platform note unlocks with the Penn Station stamp.'
      else m.locked_hint
    end
where m.title in ('Meet me under the clock', 'This way. No, that way.');

insert into public.friend_messages (
  game_id, location_id, sender_name, title, body, visibility, required, xp_value, sort_order, state,
  unlock_type, passport_stamp_key, locked_hint
)
select g.id, l.id, rows.sender, rows.title, rows.body, 'location_locked', false, 25, rows.sort, 'published',
       'passport', rows.stamp, rows.hint
from public.games g
join public.locations l on l.game_id = g.id
join (values
  ('Williamsburg', 'The group chat', 'Both Chrises', 'If you only catch one Chris, the other will never let it go.', 'williamsburg', 'A roommate note unlocks with the Williamsburg stamp.', 40),
  ('Chip City Chelsea', 'A Chelsea regular', 'Seventh Avenue sweet', 'Different shop, different tin. The cookie memory lives here.', 'chip-city-chelsea', 'A cookie memory unlocks with a Chip City stamp.', 41)
) as rows(place, sender, title, body, stamp, hint, sort) on l.title = rows.place
where g.state = 'published'
  and not exists (select 1 from public.friend_messages m where m.game_id = g.id and m.title = rows.title);

commit;
