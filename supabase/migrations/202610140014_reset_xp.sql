begin;

create or replace function public.reset_player_collection(raw_access_token text, target_installation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare player public.player_identities%rowtype;
begin
  select p.* into player from public.player_identities p
  join public.player_devices d on d.player_id = p.id
  where p.access_token_digest = extensions.digest(raw_access_token, 'sha256')
    and d.installation_id = target_installation_id and d.revoked_at is null;
  if not found then raise exception 'unauthorized' using errcode = 'P0001'; end if;

  delete from public.captures where player_id = player.id;
  delete from public.player_stamps where player_id = player.id;
  delete from public.reward_ledger where player_id = player.id;
  update public.player_identities set xp = 0 where id = player.id;
end $$;

delete from public.reward_ledger;
update public.player_identities set xp = 0;
delete from public.captures;
delete from public.player_stamps;

commit;
