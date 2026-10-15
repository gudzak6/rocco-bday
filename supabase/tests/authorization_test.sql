begin;
create extension if not exists pgtap;
select plan(12);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
  'authenticated', 'authenticated', 'organizer-a@example.test',
  crypt('password123', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.organizers(id, display_name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'Organizer A');

insert into public.games(id, organizer_id, title, recipient_name, intro_message, state, finale_title, finale_letter, finale_xp)
values (
  '11111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
  'Park Adventure', 'Alex', 'Happy birthday.', 'published',
  'The last surprise', 'You did it.', 500
);

insert into public.locations(id, game_id, title, latitude, longitude, radius_meters, max_accuracy_meters, dwell_seconds, state, fallback_code_digest)
values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'Favorite bakery', 40.7128, -74.006, 75, 100, 0, 'published',
  extensions.digest('bakery-fallback', 'sha256')
);

insert into public.characters(id, game_id, location_id, name, category, rarity, description, required, xp_value, state)
values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Cupcake Sprite', 'food', 'common', 'A cheerful pastry pal.', true, 100, 'published'
);

insert into public.friend_messages(id, game_id, sender_name, title, body, visibility, required, xp_value, state)
values (
  '44444444-4444-4444-4444-444444444444',
  '11111111-1111-1111-1111-111111111111',
  'Sam', 'Open now', 'We love you.', 'immediate', true, 50, 'published'
);

insert into public.player_identities(id, game_id, display_name, access_token_digest)
values (
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111111',
  'Alex',
  extensions.digest('player-token', 'sha256')
);

insert into public.player_devices(player_id, installation_id, name)
values (
  '55555555-5555-5555-5555-555555555555',
  '66666666-6666-6666-6666-666666666666',
  'Test iPhone'
);

select lives_ok(
  $$ select public.authorize_progress(
    'player-token', '66666666-6666-6666-6666-666666666666', 'character',
    '33333333-3333-3333-3333-333333333333', 40.7128, -74.006, 8, now() - interval '5 seconds',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', null
  ) $$,
  'character capture awards using capture reward source'
);

select is(
  (select xp from public.player_identities where id = '55555555-5555-5555-5555-555555555555'),
  100,
  'first capture grants 100 XP'
);

select lives_ok(
  $$ select public.authorize_progress(
    'player-token', '66666666-6666-6666-6666-666666666666', 'character',
    '33333333-3333-3333-3333-333333333333', 40.7128, -74.006, 8, now() - interval '5 seconds',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', null
  ) $$,
  'duplicate capture is idempotent'
);

select is(
  (select xp from public.player_identities where id = '55555555-5555-5555-5555-555555555555'),
  100,
  'duplicate capture does not grant XP again'
);

select is(
  (select count(*)::int from public.captures where player_id = '55555555-5555-5555-5555-555555555555'),
  1,
  'exactly one capture row'
);

select lives_ok(
  $$ select public.authorize_progress(
    'player-token', '66666666-6666-6666-6666-666666666666', 'message',
    '44444444-4444-4444-4444-444444444444', 0, 0, 999, now(),
    'cccccccc-cccc-cccc-cccc-cccccccccccc', null
  ) $$,
  'immediate messages skip GPS'
);

select is(
  (select xp from public.player_identities where id = '55555555-5555-5555-5555-555555555555'),
  150,
  'message unlock grants 50 XP'
);

select ok(
  (select public.finale_is_eligible('55555555-5555-5555-5555-555555555555')),
  'required published content completes finale eligibility'
);

select ok(
  exists(select 1 from public.finale_unlocks where player_id = '55555555-5555-5555-5555-555555555555'),
  'finale unlocks once required content is complete'
);

select is(
  (select xp from public.player_identities where id = '55555555-5555-5555-5555-555555555555'),
  650,
  'finale grants 500 XP exactly once'
);

select throws_ok(
  $$ select public.authorize_progress(
    'player-token', '66666666-6666-6666-6666-666666666666', 'character',
    '33333333-3333-3333-3333-333333333333', 41.0, -74.006, 8, now() - interval '5 seconds',
    'dddddddd-dddd-dddd-dddd-dddddddddddd', null
  ) $$,
  'P0001',
  'outside_radius',
  'far GPS is rejected when fallback is absent'
);

select lives_ok(
  $$ select public.authorize_progress(
    'player-token', '66666666-6666-6666-6666-666666666666', 'character',
    '33333333-3333-3333-3333-333333333333', 41.0, -74.006, 8, now(),
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'bakery-fallback'
  ) $$,
  'valid fallback code authorizes a closed venue'
);

select * from finish();
rollback;
