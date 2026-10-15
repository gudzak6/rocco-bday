begin;

create extension if not exists pgcrypto;

create type public.publication_state as enum ('draft', 'published', 'archived');
create type public.content_status as enum ('draft', 'published', 'archived');
create type public.character_category as enum ('friend', 'food', 'memory', 'inside_joke', 'legendary');
create type public.character_rarity as enum ('common', 'rare', 'legendary');
create type public.message_visibility as enum ('immediate', 'location_locked');
create type public.moderation_status as enum ('pending', 'approved', 'rejected');
create type public.invitation_kind as enum ('player', 'contributor', 'recovery');
create type public.media_kind as enum ('image', 'audio', 'video');
create type public.reward_source as enum ('capture', 'message', 'landmark', 'finale');

create table public.organizers (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.games (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references public.organizers(id) on delete restrict,
  title text not null check (char_length(title) between 1 and 100),
  recipient_name text not null check (char_length(recipient_name) between 1 and 80),
  intro_message text not null default '' check (char_length(intro_message) <= 2000),
  cover_art_path text,
  launch_at timestamptz,
  state public.publication_state not null default 'draft',
  finale_title text,
  finale_letter text,
  finale_media_path text,
  finale_destination text,
  finale_xp integer not null default 500 check (finale_xp >= 0),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index games_organizer_idx on public.games(organizer_id);

create table public.player_identities (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null unique references public.games(id) on delete cascade,
  display_name text not null,
  avatar_style jsonb not null default '{}'::jsonb,
  access_token_digest bytea not null unique,
  access_token_rotated_at timestamptz not null default now(),
  xp integer not null default 0 check (xp >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.player_devices (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  installation_id uuid not null,
  name text not null check (char_length(name) between 1 and 120),
  revoked_at timestamptz,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(player_id, installation_id)
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  address text,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  radius_meters integer not null default 75 check (radius_meters between 10 and 10000),
  max_accuracy_meters integer not null default 100 check (max_accuracy_meters between 5 and 1000),
  dwell_seconds integer not null default 8 check (dwell_seconds between 0 and 300),
  hint text check (char_length(hint) <= 500),
  fallback_code_digest bytea,
  state public.content_status not null default 'draft',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index locations_game_state_idx on public.locations(game_id, state);

create table public.characters (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  name text not null check (char_length(name) between 1 and 100),
  category public.character_category not null,
  rarity public.character_rarity not null default 'common',
  description text not null default '',
  personality text not null default '',
  special_ability text not null default '',
  artwork_path text,
  required boolean not null default false,
  xp_value integer not null default 100 check (xp_value >= 0),
  sort_order integer not null default 0,
  state public.content_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index characters_game_state_idx on public.characters(game_id, state);

create table public.friend_messages (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  sender_name text not null check (char_length(sender_name) between 1 and 80),
  title text not null default 'A birthday note' check (char_length(title) <= 120),
  body text not null check (char_length(body) between 1 and 5000),
  visibility public.message_visibility not null default 'location_locked',
  required boolean not null default false,
  xp_value integer not null default 50 check (xp_value >= 0),
  sort_order integer not null default 0,
  state public.content_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (visibility = 'immediate' or location_id is not null)
);
create index messages_game_state_idx on public.friend_messages(game_id, state);

create table public.message_media (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.friend_messages(id) on delete cascade,
  kind public.media_kind not null,
  storage_path text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size between 1 and 26214400),
  duration_seconds integer check (duration_seconds between 1 and 600),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(message_id, storage_path)
);

create table public.landmarks (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '',
  story text,
  image_path text,
  required boolean not null default false,
  xp_value integer not null default 75 check (xp_value >= 0),
  sort_order integer not null default 0,
  state public.content_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index landmarks_game_state_idx on public.landmarks(game_id, state);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  kind public.invitation_kind not null,
  token_digest bytea not null unique,
  permissions text[] not null default '{}',
  max_uses integer not null default 1 check (max_uses > 0),
  use_count integer not null default 0 check (use_count >= 0),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by uuid references public.organizers(id) on delete set null,
  created_at timestamptz not null default now(),
  check (use_count <= max_uses)
);
create index invitations_game_kind_idx on public.invitations(game_id, kind);

create table public.recovery_tokens (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  token_digest bytea not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references public.organizers(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  invitation_id uuid not null references public.invitations(id) on delete restrict,
  display_name text not null check (char_length(display_name) between 1 and 80),
  message text not null check (char_length(message) between 1 and 5000),
  location_suggestion text check (char_length(location_suggestion) <= 500),
  memory_suggestion text check (char_length(memory_suggestion) <= 2000),
  character_idea text check (char_length(character_idea) <= 1000),
  status public.moderation_status not null default 'pending',
  moderation_notes text,
  reviewed_by uuid references public.organizers(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index submissions_game_status_idx on public.submissions(game_id, status, created_at desc);

create table public.submission_media (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions(id) on delete cascade,
  kind public.media_kind not null,
  storage_path text not null unique,
  mime_type text not null,
  byte_size bigint not null check (byte_size between 1 and 26214400),
  duration_seconds integer check (duration_seconds between 1 and 600),
  created_at timestamptz not null default now()
);

create table public.captures (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  character_id uuid not null references public.characters(id) on delete restrict,
  idempotency_key uuid not null,
  captured_at timestamptz not null default now(),
  unique(player_id, character_id),
  unique(player_id, idempotency_key)
);

create table public.message_unlocks (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  message_id uuid not null references public.friend_messages(id) on delete restrict,
  idempotency_key uuid not null,
  unlocked_at timestamptz not null default now(),
  unique(player_id, message_id),
  unique(player_id, idempotency_key)
);

create table public.landmark_visits (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  landmark_id uuid not null references public.landmarks(id) on delete restrict,
  idempotency_key uuid not null,
  visited_at timestamptz not null default now(),
  unique(player_id, landmark_id),
  unique(player_id, idempotency_key)
);

create table public.reward_ledger (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.player_identities(id) on delete cascade,
  source_type public.reward_source not null,
  source_id uuid not null,
  xp integer not null check (xp >= 0),
  awarded_at timestamptz not null default now(),
  unique(player_id, source_type, source_id)
);
create index reward_ledger_player_idx on public.reward_ledger(player_id, awarded_at desc);

create table public.finale_unlocks (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null unique references public.player_identities(id) on delete cascade,
  idempotency_key uuid not null,
  unlocked_at timestamptz not null default now(),
  replayed_at timestamptz,
  unique(player_id, idempotency_key)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  game_id uuid references public.games(id) on delete set null,
  actor_id uuid,
  actor_type text not null check (actor_type in ('organizer', 'player', 'contributor', 'system')),
  action text not null,
  target_type text,
  target_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_events_game_created_idx on public.audit_events(game_id, created_at desc);

create function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array['organizers','games','player_identities','locations','characters','friend_messages','landmarks','submissions']
  loop
    execute format('create trigger set_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
  end loop;
end $$;

create function public.owns_game(target_game_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists(select 1 from public.games g where g.id = target_game_id and g.organizer_id = auth.uid()) $$;

revoke all on function public.owns_game(uuid) from public;
grant execute on function public.owns_game(uuid) to authenticated;

alter table public.organizers enable row level security;
alter table public.games enable row level security;
alter table public.player_identities enable row level security;
alter table public.player_devices enable row level security;
alter table public.locations enable row level security;
alter table public.characters enable row level security;
alter table public.friend_messages enable row level security;
alter table public.message_media enable row level security;
alter table public.landmarks enable row level security;
alter table public.invitations enable row level security;
alter table public.recovery_tokens enable row level security;
alter table public.submissions enable row level security;
alter table public.submission_media enable row level security;
alter table public.captures enable row level security;
alter table public.message_unlocks enable row level security;
alter table public.landmark_visits enable row level security;
alter table public.reward_ledger enable row level security;
alter table public.finale_unlocks enable row level security;
alter table public.audit_events enable row level security;

create policy organizer_self on public.organizers for all to authenticated
using (id = auth.uid()) with check (id = auth.uid());
create policy organizer_games on public.games for all to authenticated
using (organizer_id = auth.uid()) with check (organizer_id = auth.uid());

do $$
declare table_name text;
begin
  foreach table_name in array array['locations','characters','friend_messages','landmarks','invitations','submissions','audit_events']
  loop
    execute format('create policy organizer_game_scope on public.%I for all to authenticated using (public.owns_game(game_id)) with check (public.owns_game(game_id))', table_name);
  end loop;
end $$;

create policy organizer_players on public.player_identities for all to authenticated
using (public.owns_game(game_id)) with check (public.owns_game(game_id));
create policy organizer_devices on public.player_devices for all to authenticated
using (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)))
with check (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)));
create policy organizer_recovery on public.recovery_tokens for all to authenticated
using (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)))
with check (exists(select 1 from public.player_identities p where p.id = player_id and public.owns_game(p.game_id)));
create policy organizer_message_media on public.message_media for all to authenticated
using (exists(select 1 from public.friend_messages m where m.id = message_id and public.owns_game(m.game_id)))
with check (exists(select 1 from public.friend_messages m where m.id = message_id and public.owns_game(m.game_id)));
create policy organizer_submission_media on public.submission_media for all to authenticated
using (exists(select 1 from public.submissions s where s.id = submission_id and public.owns_game(s.game_id)))
with check (exists(select 1 from public.submissions s where s.id = submission_id and public.owns_game(s.game_id)));

do $$
declare table_name text;
declare player_column text := 'player_id';
begin
  foreach table_name in array array['captures','message_unlocks','landmark_visits','reward_ledger','finale_unlocks']
  loop
    execute format('create policy organizer_progress on public.%I for select to authenticated using (exists(select 1 from public.player_identities p where p.id = %I and public.owns_game(p.game_id)))', table_name, player_column);
  end loop;
end $$;

create function public.apply_reward(
  target_player_id uuid,
  reward_kind public.reward_source,
  target_source_id uuid,
  amount integer
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare inserted_count integer;
begin
  if amount < 0 then raise exception 'invalid reward'; end if;
  insert into public.reward_ledger(player_id, source_type, source_id, xp)
  values (target_player_id, reward_kind, target_source_id, amount)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 1 then
    update public.player_identities set xp = xp + amount where id = target_player_id;
    return true;
  end if;
  return false;
end $$;
revoke all on function public.apply_reward(uuid, public.reward_source, uuid, integer) from public, anon, authenticated;
grant execute on function public.apply_reward(uuid, public.reward_source, uuid, integer) to service_role;

create function public.finale_is_eligible(target_player_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select
    not exists (
      select 1 from public.characters c
      join public.player_identities p on p.game_id = c.game_id and p.id = target_player_id
      where c.required and c.state = 'published'
      and not exists (select 1 from public.captures x where x.player_id = p.id and x.character_id = c.id)
    )
    and not exists (
      select 1 from public.friend_messages m
      join public.player_identities p on p.game_id = m.game_id and p.id = target_player_id
      where m.required and m.state = 'published'
      and not exists (select 1 from public.message_unlocks u where u.player_id = p.id and u.message_id = m.id)
    )
    and not exists (
      select 1 from public.landmarks l
      join public.player_identities p on p.game_id = l.game_id and p.id = target_player_id
      where l.required and l.state = 'published'
      and not exists (select 1 from public.landmark_visits v where v.player_id = p.id and v.landmark_id = l.id)
    )
$$;
revoke all on function public.finale_is_eligible(uuid) from public, anon, authenticated;
grant execute on function public.finale_is_eligible(uuid) to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('public-artwork', 'public-artwork', true, 10485760, array['image/jpeg','image/png','image/webp']),
  ('private-media', 'private-media', false, 26214400, array['image/jpeg','image/png','image/webp','audio/mpeg','audio/mp4','audio/x-m4a','video/mp4']),
  ('submission-quarantine', 'submission-quarantine', false, 26214400, array['image/jpeg','image/png','image/webp','audio/mpeg','audio/mp4','audio/x-m4a'])
on conflict (id) do nothing;

create policy organizer_storage_read on storage.objects for select to authenticated
using (
  bucket_id in ('public-artwork','private-media','submission-quarantine')
  and public.owns_game(((storage.foldername(name))[1])::uuid)
);
create policy organizer_storage_write on storage.objects for insert to authenticated
with check (
  bucket_id in ('public-artwork','private-media')
  and public.owns_game(((storage.foldername(name))[1])::uuid)
);
create policy organizer_storage_update on storage.objects for update to authenticated
using (public.owns_game(((storage.foldername(name))[1])::uuid))
with check (public.owns_game(((storage.foldername(name))[1])::uuid));
create policy organizer_storage_delete on storage.objects for delete to authenticated
using (public.owns_game(((storage.foldername(name))[1])::uuid));

commit;
