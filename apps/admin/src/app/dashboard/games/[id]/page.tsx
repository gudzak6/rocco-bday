import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { MapPinPicker } from "@/components/map-pin-picker";
import { ConfirmField } from "@/components/confirm-field";
import {
  archiveContent, createCharacter, createEggType, createInvite, createLandmark, createLocation, createMessage,
  createRecovery, grantPlayerEgg, moderateSubmission, publishGame, publishMessage, resetTestEggs, revokeDevice,
  saveEggRewards, saveFinale, seedAdventureCheckpoints, seedExampleContent, setLocationFallback, unpublishGame,
  updateCharacter, updateEggType, updateGame, updateLandmark, updateLocation, updateMessage, uploadCharacterArtwork,
  uploadCoverArt,
} from "../../actions";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ invite?: string; kind?: string }> };

export default async function GameEditor({ params, searchParams }: Props) {
  const { id } = await params;
  const invite = await searchParams;
  const supabase = await createClient();
  const [
    gameResult, locationsResult, charactersResult, messagesResult,
    landmarksResult, submissionsResult, playersResult, devicesResult,
    eggTypesResult, eggRewardsResult, playerEggsResult,
  ] = await Promise.all([
    supabase.from("games").select("*").eq("id", id).single(),
    supabase.from("locations").select("*").eq("game_id", id).neq("state", "archived").order("sort_order"),
    supabase.from("characters").select("*").eq("game_id", id).neq("state", "archived").order("sort_order"),
    supabase.from("friend_messages").select("id,title,sender_name,visibility,required,state,location_id,body,unlock_type,unlock_rule,character_id,passport_stamp_key,locked_hint,reveal_sender_when_locked,xp_value,sender_photo_path").eq("game_id", id).neq("state", "archived"),
    supabase.from("landmarks").select("id,title,required,state,location_id,description,story,xp_value").eq("game_id", id).neq("state", "archived"),
    supabase.from("submissions").select("*, submission_media(*)").eq("game_id", id).eq("status", "pending").order("created_at"),
    supabase.from("player_identities").select("id,xp,display_name").eq("game_id", id),
    supabase.from("player_devices").select("id,name,installation_id,revoked_at,last_seen_at,player_id"),
    supabase.from("egg_types").select("*").eq("game_id", id).neq("state", "archived").order("sort_order"),
    supabase.from("egg_type_rewards").select("egg_type_id,character_id,weight"),
    supabase.from("player_eggs").select("id,egg_type_id,status,meters_walked,is_test,player_id"),
  ]);
  if (gameResult.error) notFound();
  const game = gameResult.data;
  const locations = locationsResult.data ?? [];
  const characters = charactersResult.data ?? [];
  const messages = messagesResult.data ?? [];
  const landmarks = landmarksResult.data ?? [];
  const playerIds = new Set((playersResult.data ?? []).map((player) => player.id));
  const devices = (devicesResult.data ?? []).filter((device) => playerIds.has(device.player_id));
  const eggTypes = eggTypesResult.data ?? [];
  const eggRewards = eggRewardsResult.data ?? [];
  const grantedEggs = playerEggsResult.data ?? [];
  const players = playersResult.data ?? [];
  const launchValue = game.launch_at ? new Date(game.launch_at).toISOString().slice(0, 16) : "";

  return (
    <div className="space-y-8 py-8">
      <Link href="/dashboard" className="font-bold text-[var(--purple)]">← All adventures</Link>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="font-bold uppercase text-[var(--purple)]">{game.state}</p>
          <h1 className="text-4xl font-black">{game.title}</h1>
          <p>For {game.recipient_name}</p>
          {game.open_play && game.state === "published" && (
            <p className="mt-2 text-sm text-slate-600">Players can tap Start in the iPhone app — no invite code required.</p>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          {locations.length === 0 && (
            <form action={seedExampleContent.bind(null, id)}>
              <button className="button secondary">Load example content</button>
            </form>
          )}
          <form action={seedAdventureCheckpoints.bind(null, id)}>
            <button className="button secondary">Add NYC birthday checkpoints</button>
          </form>
          <Link className="button secondary" href={`/api/games/${id}/export`}>Export</Link>
          <form action={createInvite.bind(null, id, "player")}><button className="button secondary">Optional player invite</button></form>
          <form action={createRecovery.bind(null, id)}><button className="button secondary">Recovery code</button></form>
          <form action={createInvite.bind(null, id, "contributor")}><button className="button secondary">Contributor link</button></form>
          {game.state === "published"
            ? (
              <form action={unpublishGame.bind(null, id)} className="card space-y-2 p-3">
                <ConfirmField expected="UNPUBLISH" label="Type UNPUBLISH">
                  <button className="button">Unpublish</button>
                </ConfirmField>
              </form>
            )
            : <form action={publishGame.bind(null, id)}><button className="button">Validate & publish</button></form>}
        </div>
      </div>

      {invite.invite && (
        <aside className="card border-2 border-[var(--gold)] p-5" role="status">
          <strong>Copy this {invite.kind} secret now — it will not be shown again.</strong>
          <code className="mt-2 block break-all rounded-lg bg-slate-100 p-3">
            {invite.kind === "contributor"
              ? `${process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"}/contribute?token=${invite.invite}`
              : invite.kind === "player"
                ? `birthdaygo://invite?code=${invite.invite}`
                : invite.invite}
          </code>
          {invite.kind === "player" && (
            <p className="mt-2 text-sm">The recipient can paste the code in the app if the deep link is not used.</p>
          )}
        </aside>
      )}

      <section className="grid gap-4 md:grid-cols-4" aria-label="Game status">
        <Stat label="Locations" value={locations.length} />
        <Stat label="Characters" value={characters.length} />
        <Stat label="Notes" value={messages.length} />
        <Stat label="Player XP" value={playersResult.data?.[0]?.xp ?? 0} />
      </section>

      <EditorSection title="Adventure setup" description="Recipient, welcome copy, launch time, and cover art. Nothing here is public.">
        <form action={updateGame.bind(null, id)} className="grid gap-3 md:grid-cols-2">
          <TextInput name="title" label="Game title" required defaultValue={game.title} />
          <TextInput name="recipientName" label="Recipient name" required defaultValue={game.recipient_name} />
          <label className="md:col-span-2">Welcome message<textarea className="field mt-1" name="introMessage" maxLength={2000} defaultValue={game.intro_message ?? ""} /></label>
          <label>Launch at (optional)<input className="field mt-1" type="datetime-local" name="launchAt" defaultValue={launchValue} /></label>
          <button className="button">Save setup</button>
        </form>
        <form action={uploadCoverArt.bind(null, id)} className="flex flex-wrap items-end gap-3">
          <label>Cover artwork<input className="field mt-1" type="file" name="cover" accept="image/jpeg,image/png,image/webp" required /></label>
          <button className="button secondary">Upload cover</button>
          {game.cover_art_path && <span className="text-sm text-slate-600">Cover on file.</span>}
        </form>
      </EditorSection>

      <EditorSection title="1. Meaningful places" description="Click the map or drag the pin. Default unlock radius is 75 meters. Set a fallback code for closed venues and accessibility.">
        <form action={createLocation.bind(null, id)} className="grid gap-4 lg:grid-cols-2">
          <div className="space-y-3">
            <label className="block font-bold">Place title<input className="field mt-1" name="title" required maxLength={120} /></label>
            <label className="block font-bold">Address label<input className="field mt-1" name="address" maxLength={500} /></label>
            <label className="block font-bold">Hint<textarea className="field mt-1" name="hint" maxLength={500} /></label>
            <label className="block font-bold">Unlock radius (meters)<input className="field mt-1" name="radius" type="number" defaultValue={75} min={10} max={10000} required /></label>
          </div>
          <MapPinPicker />
          <button className="button lg:col-span-2">Add location</button>
        </form>
        <ul className="space-y-3">
          {locations.map((item) => (
            <li className="rounded-xl bg-slate-50 p-4" key={item.id}>
              <p className="font-bold">{item.title} · {item.radius_meters} m · {item.state}</p>
              <p className="text-sm text-slate-600">{item.address} {item.hint}</p>
              <form action={updateLocation.bind(null, id, item.id)} className="mt-3 grid gap-2 md:grid-cols-2">
                <TextInput name="title" label="Title" required defaultValue={item.title} />
                <TextInput name="address" label="Organizer address (not shown on the player map)" defaultValue={item.address ?? ""} />
                <label className="md:col-span-2">Hint<textarea className="field mt-1" name="hint" maxLength={500} defaultValue={item.hint ?? ""} /></label>
                <TextInput name="latitude" label="Latitude" required defaultValue={String(item.latitude)} />
                <TextInput name="longitude" label="Longitude" required defaultValue={String(item.longitude)} />
                <TextInput name="radius" label="Radius meters" required defaultValue={String(item.radius_meters)} />
                <button className="button secondary">Save place</button>
              </form>
              <div className="mt-3 flex flex-wrap gap-3">
                <form action={setLocationFallback.bind(null, id, item.id)} className="flex gap-2">
                  <input className="field" name="fallbackCode" minLength={6} maxLength={32} placeholder="Fallback code" required />
                  <button className="button secondary">Set fallback</button>
                </form>
                <ArchiveForm gameId={id} table="locations" id={item.id} published={item.state === "published"} />
              </div>
            </li>
          ))}
        </ul>
      </EditorSection>

      <EditorSection title="2. Original characters" description="Use original artwork only. Uncaught characters reveal silhouettes, never private details.">
        <form action={createCharacter.bind(null, id)} className="grid gap-3 md:grid-cols-2">
          <TextInput name="name" label="Name" required />
          <SelectLocation locations={locations} />
          <label>Category<select className="field mt-1" name="category">{["friend","food","memory","inside_joke","legendary"].map((value) => <option key={value}>{value}</option>)}</select></label>
          <label>Rarity<select className="field mt-1" name="rarity">{["common","rare","legendary"].map((value) => <option key={value}>{value}</option>)}</select></label>
          <label className="md:col-span-2">Description<textarea className="field mt-1" name="description" required maxLength={3000} /></label>
          <TextInput name="personality" label="Personality" />
          <TextInput name="specialAbility" label="Special ability" />
          <label>Original artwork<input className="field mt-1" type="file" name="artwork" accept="image/jpeg,image/png,image/webp" /></label>
          <RequiredToggle />
          <button className="button md:col-span-2">Add character</button>
        </form>
        <ul className="space-y-3">
          {characters.map((item) => (
            <li className="rounded-xl bg-slate-50 p-4" key={item.id}>
              <p className="font-bold">{item.name} · {item.rarity} · {item.state}{item.required ? " · required" : ""}</p>
              <form action={updateCharacter.bind(null, id, item.id)} className="mt-3 grid gap-2 md:grid-cols-2">
                <TextInput name="name" label="Name" required defaultValue={item.name} />
                <TextInput name="xp" label="XP" required defaultValue={String(item.xp_value ?? 100)} />
                <label className="md:col-span-2">Description<textarea className="field mt-1" name="description" required maxLength={3000} defaultValue={item.description ?? ""} /></label>
                <TextInput name="personality" label="Personality" defaultValue={item.personality ?? ""} />
                <TextInput name="specialAbility" label="Special ability" defaultValue={item.special_ability ?? ""} />
                <button className="button secondary md:col-span-2">Save character</button>
              </form>
              <form action={uploadCharacterArtwork.bind(null, id, item.id)} className="mt-2 flex flex-wrap gap-2">
                <input className="field" type="file" name="artwork" accept="image/jpeg,image/png,image/webp" required />
                <button className="button secondary">Upload art</button>
              </form>
              <ArchiveForm gameId={id} table="characters" id={item.id} published={item.state === "published"} />
            </li>
          ))}
        </ul>
      </EditorSection>

      <EditorSection title="3. Birthday Notes" description="Approve, assign unlocks, and preview the iOS letter. Locked bodies stay server-protected until the recipient earns them.">
        <form action={createMessage.bind(null, id)} className="grid gap-3 md:grid-cols-2">
          <TextInput name="senderName" label="Sender" required />
          <TextInput name="title" label="Envelope title" required />
          <label>Unlock method
            <select className="field mt-1" name="unlockType" defaultValue="immediate">
              <option value="immediate">Immediately available</option>
              <option value="location">Location-based</option>
              <option value="character">Character-based</option>
              <option value="passport">Passport stamp</option>
              <option value="composite">Multiple prerequisites</option>
            </select>
          </label>
          <label>If multiple prerequisites
            <select className="field mt-1" name="unlockRule" defaultValue="all">
              <option value="all">ALL must be met</option>
              <option value="any">ANY one is enough</option>
            </select>
          </label>
          <SelectLocation locations={locations} optional />
          <SelectCharacter characters={characters} />
          <SelectStamp />
          <TextInput name="lockedHint" label="Spoiler-safe locked hint" />
          <TextInput name="xp" label="Optional XP" defaultValue="25" />
          <label className="md:col-span-2">Birthday message<textarea className="field mt-1" name="body" required maxLength={5000} rows={5} /></label>
          <label>Sender photo<input className="field mt-1" type="file" name="senderPhoto" accept="image/jpeg,image/png,image/webp" /></label>
          <label>Note photo<input className="field mt-1" type="file" name="photo" accept="image/jpeg,image/png,image/webp" /></label>
          <label className="md:col-span-2">Voice recording<input className="field mt-1" type="file" name="audio" accept="audio/mpeg,audio/mp4,audio/x-m4a" /></label>
          <label className="flex items-center gap-2"><input type="checkbox" name="revealSender" /> Reveal sender while locked</label>
          <label className="flex items-center gap-2"><input type="checkbox" name="publish" /> Publish now</label>
          <RequiredToggle />
          <button className="button md:col-span-2">Create birthday note</button>
        </form>
        <ul className="space-y-3">
          {messages.map((item) => (
            <li className="rounded-xl bg-slate-50 p-4" key={item.id}>
              <p className="font-bold">{item.title} · {item.unlock_type ?? item.visibility} · {item.state}</p>
              <div className="mt-3 rounded-2xl bg-[#f8f7fc] p-4 shadow-sm">
                <p className="text-xs font-bold uppercase tracking-wide text-[var(--purple)]">iOS letter preview</p>
                <p className="text-xl font-black">{item.title}</p>
                <p className="text-sm text-slate-600">From {item.sender_name}</p>
                <p className="mt-2 whitespace-pre-wrap text-sm">{item.body}</p>
                {item.locked_hint && <p className="mt-2 text-xs text-slate-500">Locked hint: {item.locked_hint}</p>}
              </div>
              <form action={updateMessage.bind(null, id, item.id)} className="mt-3 grid gap-2 md:grid-cols-2">
                <TextInput name="senderName" label="Sender" required defaultValue={item.sender_name} />
                <TextInput name="title" label="Title" required defaultValue={item.title} />
                <label>Unlock method
                  <select className="field mt-1" name="unlockType" defaultValue={item.unlock_type ?? (item.visibility === "immediate" ? "immediate" : "location")}>
                    <option value="immediate">Immediately available</option>
                    <option value="location">Location-based</option>
                    <option value="character">Character-based</option>
                    <option value="passport">Passport stamp</option>
                    <option value="composite">Multiple prerequisites</option>
                  </select>
                </label>
                <label>If multiple prerequisites
                  <select className="field mt-1" name="unlockRule" defaultValue={item.unlock_rule ?? "all"}>
                    <option value="all">ALL must be met</option>
                    <option value="any">ANY one is enough</option>
                  </select>
                </label>
                <SelectLocation locations={locations} optional defaultValue={item.location_id ?? ""} />
                <SelectCharacter characters={characters} defaultValue={item.character_id ?? ""} />
                <SelectStamp defaultValue={item.passport_stamp_key ?? ""} />
                <TextInput name="lockedHint" label="Spoiler-safe locked hint" defaultValue={item.locked_hint ?? ""} />
                <TextInput name="xp" label="Optional XP" defaultValue={String(item.xp_value ?? 25)} />
                <label className="md:col-span-2">Message<textarea className="field mt-1" name="body" required maxLength={5000} rows={4} defaultValue={item.body ?? ""} /></label>
                <label>Replace photo<input className="field mt-1" type="file" name="photo" accept="image/jpeg,image/png,image/webp" /></label>
                <label>Replace audio<input className="field mt-1" type="file" name="audio" accept="audio/mpeg,audio/mp4,audio/x-m4a" /></label>
                <label className="flex items-center gap-2 md:col-span-2"><input type="checkbox" name="revealSender" defaultChecked={item.reveal_sender_when_locked === true} /> Reveal sender while locked</label>
                <button className="button secondary md:col-span-2">Save note</button>
              </form>
              {item.state !== "published" && (
                <form action={publishMessage.bind(null, id, item.id)} className="mt-2">
                  <button className="button">Publish approved note</button>
                </form>
              )}
              <ArchiveForm gameId={id} table="friend_messages" id={item.id} published={item.state === "published"} />
            </li>
          ))}
        </ul>
      </EditorSection>

      <EditorSection title="4. Memory landmarks" description="Visiting each landmark grants a one-time reward.">
        <form action={createLandmark.bind(null, id)} className="grid gap-3 md:grid-cols-2">
          <TextInput name="title" label="Title" required />
          <SelectLocation locations={locations} />
          <label className="md:col-span-2">Description<textarea className="field mt-1" name="description" required maxLength={3000} /></label>
          <label className="md:col-span-2">Optional story<textarea className="field mt-1" name="story" maxLength={5000} /></label>
          <label>Landmark photo<input className="field mt-1" type="file" name="image" accept="image/jpeg,image/png,image/webp" /></label>
          <RequiredToggle />
          <button className="button md:col-span-2">Add landmark</button>
        </form>
        <ul className="space-y-3">
          {landmarks.map((item) => (
            <li className="rounded-xl bg-slate-50 p-4" key={item.id}>
              <p className="font-bold">{item.title} · {item.state}{item.required ? " · required" : ""}</p>
              <form action={updateLandmark.bind(null, id, item.id)} className="mt-3 grid gap-2">
                <TextInput name="title" label="Title" required defaultValue={item.title} />
                <TextInput name="xp" label="XP" required defaultValue={String(item.xp_value ?? 75)} />
                <label>Description<textarea className="field mt-1" name="description" required maxLength={3000} defaultValue={item.description ?? ""} /></label>
                <label>Story<textarea className="field mt-1" name="story" maxLength={5000} defaultValue={item.story ?? ""} /></label>
                <button className="button secondary">Save Memory Stop</button>
              </form>
              <ArchiveForm gameId={id} table="landmarks" id={item.id} published={item.state === "published"} />
            </li>
          ))}
        </ul>
      </EditorSection>

      <EditorSection title="5. Eggs" description="Configure walking-distance eggs, reward pools, and grants. Test resets only change eggs marked as test grants.">
        <form action={createEggType.bind(null, id)} className="grid gap-3 md:grid-cols-2">
          <TextInput name="typeKey" label="Stable key (one-mile)" required />
          <TextInput name="title" label="Title" required defaultValue="1-Mile Egg" />
          <TextInput name="requiredMeters" label="Required meters" required defaultValue="1609.344" />
          <TextInput name="xp" label="Hatch XP" required defaultValue="50" />
          <label>Artwork style
            <select className="field mt-1" name="artworkStyle" defaultValue="sky">
              <option value="sky">Pastel blue 1-mile</option>
              <option value="gold">Golden-purple 10-mile</option>
            </select>
          </label>
          <TextInput name="rarityLabel" label="Reward rarity label" required defaultValue="Common or rare" />
          <TextInput name="duplicateXp" label="Duplicate XP" required defaultValue="15" />
          <fieldset className="md:col-span-2">
            <legend className="font-semibold">Eligible rarities</legend>
            <label className="mr-3"><input type="checkbox" name="rarities" value="common" defaultChecked /> Common</label>
            <label className="mr-3"><input type="checkbox" name="rarities" value="rare" defaultChecked /> Rare</label>
            <label><input type="checkbox" name="rarities" value="legendary" /> Legendary</label>
          </fieldset>
          <label className="flex items-center gap-2 md:col-span-2"><input type="checkbox" name="excludeDuplicates" defaultChecked /> Exclude already-collected characters</label>
          <button className="button md:col-span-2">Create egg type</button>
        </form>
        <ul className="space-y-4">
          {eggTypes.map((egg) => {
            const assigned = new Set(eggRewards.filter((row) => row.egg_type_id === egg.id).map((row) => row.character_id));
            return (
              <li className="rounded-xl bg-slate-50 p-4" key={egg.id}>
                <p className="font-bold">{egg.title} · {(egg.required_meters / 1609.344).toFixed(1)} miles · {egg.xp_value} XP</p>
                <EggHatchPreview style={egg.artwork_style} />
                <form action={updateEggType.bind(null, id, egg.id)} className="mt-3 grid gap-2 md:grid-cols-2">
                  <TextInput name="title" label="Title" required defaultValue={egg.title} />
                  <TextInput name="requiredMeters" label="Required meters" required defaultValue={String(egg.required_meters)} />
                  <TextInput name="xp" label="Hatch XP" required defaultValue={String(egg.xp_value)} />
                  <TextInput name="duplicateXp" label="Duplicate XP" required defaultValue={String(egg.duplicate_xp)} />
                  <TextInput name="rarityLabel" label="Rarity label" required defaultValue={egg.rarity_label} />
                  <label>Artwork style
                    <select className="field mt-1" name="artworkStyle" defaultValue={egg.artwork_style}>
                      <option value="sky">Pastel blue 1-mile</option>
                      <option value="gold">Golden-purple 10-mile</option>
                    </select>
                  </label>
                  <fieldset className="md:col-span-2">
                    <legend className="font-semibold">Eligible rarities</legend>
                    {["common", "rare", "legendary"].map((rarity) => (
                      <label className="mr-3" key={rarity}>
                        <input type="checkbox" name="rarities" value={rarity} defaultChecked={(egg.allowed_rarities ?? []).includes(rarity)} /> {rarity}
                      </label>
                    ))}
                  </fieldset>
                  <label className="flex items-center gap-2 md:col-span-2">
                    <input type="checkbox" name="excludeDuplicates" defaultChecked={egg.exclude_duplicates !== false} /> Exclude duplicates
                  </label>
                  <label className="md:col-span-2">Egg artwork<input className="field mt-1" type="file" name="artwork" accept="image/jpeg,image/png,image/webp" /></label>
                  <button className="button secondary md:col-span-2">Save egg type</button>
                </form>
                <form action={saveEggRewards.bind(null, id, egg.id)} className="mt-3 space-y-2">
                  <p className="font-semibold">Character reward pool</p>
                  {characters.map((character) => (
                    <label className="flex items-center gap-2 text-sm" key={character.id}>
                      <input type="checkbox" name="characterId" value={character.id} defaultChecked={assigned.has(character.id)} />
                      <span>{character.name} ({character.rarity})</span>
                      <input className="field w-20" name={`weight-${character.id}`} defaultValue={String(eggRewards.find((row) => row.egg_type_id === egg.id && row.character_id === character.id)?.weight ?? 1)} />
                    </label>
                  ))}
                  <button className="button secondary">Save reward pool</button>
                </form>
              </li>
            );
          })}
        </ul>
        <form action={grantPlayerEgg.bind(null, id)} className="grid gap-3 md:grid-cols-2">
          <label>Player
            <select className="field mt-1" name="playerId" required>
              <option value="">Select player</option>
              {players.map((player) => <option value={player.id} key={player.id}>{player.display_name}</option>)}
            </select>
          </label>
          <label>Egg type
            <select className="field mt-1" name="eggTypeId" required>
              <option value="">Select egg</option>
              {eggTypes.map((egg) => <option value={egg.id} key={egg.id}>{egg.title}</option>)}
            </select>
          </label>
          <label className="flex items-center gap-2 md:col-span-2"><input type="checkbox" name="isTest" /> Mark as test grant (safe to reset)</label>
          <button className="button md:col-span-2">Grant egg</button>
        </form>
        <form action={resetTestEggs.bind(null, id)}>
          <button className="button secondary">Reset test egg progress</button>
        </form>
        <p className="text-sm text-slate-600">{grantedEggs.length} granted egg(s). Production eggs are left alone by the test reset.</p>
      </EditorSection>

      <EditorSection title="6. Final surprise" description="Required content controls eligibility; optional content never blocks completion.">
        <form action={saveFinale.bind(null, id)} className="space-y-3">
          <TextInput name="title" label="Finale title" required defaultValue={game.finale_title ?? ""} />
          <label className="block">Final letter<textarea className="field mt-1" name="letter" required rows={6} defaultValue={game.finale_letter ?? ""} /></label>
          <TextInput name="destination" label="Optional destination or gift reveal" defaultValue={game.finale_destination ?? ""} />
          <label>Optional finale media<input className="field mt-1" type="file" name="media" accept="image/jpeg,image/png,image/webp,video/mp4,audio/mpeg,audio/mp4" /></label>
          <button className="button">Save finale</button>
        </form>
      </EditorSection>

      <EditorSection title="Player preview" description="What the recipient can discover after publish. Locked note bodies are never listed here in full because the portal uses organizer credentials.">
        <ol className="list-decimal space-y-2 pl-5">
          {locations.map((place) => (
            <li key={place.id}>
              <strong>{place.title}</strong>
              <ul className="ml-4 list-disc text-sm text-slate-600">
                {characters.filter((item) => item.location_id === place.id).map((item) => <li key={item.id}>Character: {item.name}</li>)}
                {messages.filter((item) => item.location_id === place.id).map((item) => <li key={item.id}>Note: {item.title} ({item.unlock_type ?? item.visibility}{item.state === "published" ? "" : ", unpublished"})</li>)}
                {landmarks.filter((item) => item.location_id === place.id).map((item) => <li key={item.id}>Landmark: {item.title}</li>)}
              </ul>
            </li>
          ))}
        </ol>
      </EditorSection>

      <EditorSection title="Devices" description="Revoke a lost phone. Issue a recovery code so the recipient can reinstall.">
        <ul className="space-y-3">
          {devices.map((device) => (
            <li className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-slate-50 p-4" key={device.id}>
              <span>
                <strong>{device.name}</strong>
                <span className="block text-sm text-slate-600">
                  {device.revoked_at ? "Revoked" : "Active"} · last seen {new Date(device.last_seen_at).toLocaleString()}
                </span>
              </span>
              {!device.revoked_at && (
                <form action={revokeDevice.bind(null, id, device.id)}>
                  <button className="button secondary">Revoke access</button>
                </form>
              )}
            </li>
          ))}
          {!devices.length && <p className="text-slate-600">No recipient device has redeemed an invite yet.</p>}
        </ul>
      </EditorSection>

      <EditorSection title={`Pending contributions (${submissionsResult.data?.length ?? 0})`} description="Friends submit from the public contribution page without installing the app. Approving creates a draft Birthday Note. Publish it after you assign unlocks.">
        <div className="space-y-3">
          {(submissionsResult.data ?? []).map((submission) => (
            <article className="rounded-xl border p-4" key={submission.id}>
              <h3 className="font-black">{submission.display_name}</h3>
              <p className="my-3 whitespace-pre-wrap">{submission.message}</p>
              {submission.location_suggestion && <p><strong>Place idea:</strong> {submission.location_suggestion}</p>}
              {submission.memory_suggestion && <p><strong>Memory:</strong> {submission.memory_suggestion}</p>}
              {submission.character_idea && <p><strong>Character idea:</strong> {submission.character_idea}</p>}
              <p className="text-sm text-slate-600">{submission.submission_media?.length ?? 0} attached file(s)</p>
              <div className="mt-3 flex gap-2">
                <form action={moderateSubmission.bind(null, id, submission.id, "approved")}><button className="button">Approve as draft note</button></form>
                <form action={moderateSubmission.bind(null, id, submission.id, "rejected")}><button className="button secondary">Reject</button></form>
              </div>
            </article>
          ))}
        </div>
      </EditorSection>
    </div>
  );
}

function ArchiveForm({ gameId, table, id, published }: { gameId: string; table: string; id: string; published: boolean }) {
  return (
    <form action={archiveContent.bind(null, gameId, table, id)} className="mt-2">
      {published
        ? (
          <ConfirmField expected="ARCHIVE" label="Type ARCHIVE to archive published content">
            <button className="button secondary">Archive</button>
          </ConfirmField>
        )
        : <button className="button secondary" name="confirmation" value="">Archive draft</button>}
    </form>
  );
}

function EditorSection({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return <section className="card space-y-5 p-6"><div><h2 className="text-2xl font-black">{title}</h2><p className="text-slate-600">{description}</p></div>{children}</section>;
}
function Stat({ label, value }: { label: string; value: number }) {
  return <div className="card p-4"><strong className="text-2xl">{value}</strong><span className="block text-sm text-slate-600">{label}</span></div>;
}
function TextInput({ name, label, required, defaultValue }: { name: string; label: string; required?: boolean; defaultValue?: string }) {
  return <label className="block">{label}<input className="field mt-1" name={name} required={required} defaultValue={defaultValue} /></label>;
}
function SelectLocation({ locations, optional, defaultValue }: { locations: Array<{ id: string; title: string }>; optional?: boolean; defaultValue?: string }) {
  return <label>Location<select className="field mt-1" name="locationId" required={!optional} defaultValue={defaultValue}><option value="">No map pin</option>{locations.map((item) => <option value={item.id} key={item.id}>{item.title}</option>)}</select></label>;
}
function SelectCharacter({ characters, defaultValue }: { characters: Array<{ id: string; name: string }>; defaultValue?: string }) {
  return <label>Character association<select className="field mt-1" name="characterId" defaultValue={defaultValue}><option value="">None</option>{characters.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label>;
}
function SelectStamp({ defaultValue }: { defaultValue?: string }) {
  const stamps = [
    ["grand-central", "Grand Central"],
    ["penn-station", "Penn Station"],
    ["runcenter", "NYRR RUNCENTER"],
    ["chip-city-rockefeller", "Chip City Rockefeller"],
    ["chip-city-chelsea", "Chip City Chelsea"],
    ["williamsburg", "Williamsburg"],
    ["upper-east-side", "Upper East Side"],
  ];
  return <label>Passport stamp<select className="field mt-1" name="passportStampKey" defaultValue={defaultValue}><option value="">None</option>{stamps.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>;
}
function RequiredToggle() {
  return <label className="flex items-center gap-2"><input type="checkbox" name="required" /> Required for finale</label>;
}
function EggHatchPreview({ style }: { style: string }) {
  const gold = style === "gold";
  return (
    <div className="mt-3 rounded-xl bg-white p-4">
      <p className="mb-2 text-sm font-semibold">Hatch preview</p>
      <div className={`egg-preview ${gold ? "egg-gold" : "egg-sky"}`} aria-hidden />
      <style>{`
        .egg-preview { width: 72px; height: 96px; border-radius: 50% 50% 50% 50% / 60% 60% 40% 40%; margin: 0 auto; animation: egg-shake 1.4s ease-in-out infinite; }
        .egg-sky { background: linear-gradient(#b8e4ff, #66c9f2); box-shadow: 0 0 12px #66c9f2; }
        .egg-gold { background: linear-gradient(#b07af2, #ffc857); box-shadow: 0 0 16px #ffc857; }
        @keyframes egg-shake { 0%,100% { transform: rotate(0deg); } 25% { transform: rotate(-8deg); } 75% { transform: rotate(8deg); } }
        @media (prefers-reduced-motion: reduce) { .egg-preview { animation: none; } }
      `}</style>
    </div>
  );
}
