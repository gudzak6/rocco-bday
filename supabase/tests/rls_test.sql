begin;
create extension if not exists pgtap;
select plan(13);

select has_table('public', 'games', 'games exists');
select has_table('public', 'reward_ledger', 'reward ledger exists');
select has_column('public', 'player_devices', 'revoked_at', 'devices can be revoked');
select col_is_unique('public', 'captures', array['player_id', 'character_id'], 'captures are exactly once');
select col_is_unique('public', 'reward_ledger', array['player_id', 'source_type', 'source_id'], 'rewards are exactly once');
select col_is_unique('public', 'message_unlocks', array['player_id', 'message_id'], 'message unlocks are exactly once');
select col_is_unique('public', 'landmark_visits', array['player_id', 'landmark_id'], 'landmark visits are exactly once');
select col_is_unique('public', 'player_identities', array['game_id'], 'one player identity per game');

select policies_are('public', 'games', array['organizer_games'], 'games have only organizer policy');
select policies_are('public', 'friend_messages', array['organizer_game_scope'], 'private messages have no anonymous/player direct policy');
select policies_are('public', 'submissions', array['organizer_game_scope'], 'contributors cannot directly insert submissions');
select policies_are('public', 'captures', array['organizer_progress'], 'captures are not writable by anon or authenticated players');
select policies_are('public', 'reward_ledger', array['organizer_progress'], 'reward ledger is organizer-read only');

select * from finish();
rollback;
