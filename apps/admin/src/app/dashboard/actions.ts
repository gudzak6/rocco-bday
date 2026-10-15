"use server";

import { GameInput } from "@birthday-go/shared";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

async function organizer() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) redirect("/login");
  return { supabase, user: data.user };
}

function refresh(gameId: string) {
  revalidatePath(`/dashboard/games/${gameId}`);
}

export async function createGame(formData: FormData) {
  const input = GameInput.parse({
    title: formData.get("title"),
    recipientName: formData.get("recipientName"),
    introMessage: formData.get("introMessage"),
    launchAt: null,
  });
  const { supabase, user } = await organizer();
  const { data, error } = await supabase.from("games").insert({
    organizer_id: user.id,
    title: input.title,
    recipient_name: input.recipientName,
    intro_message: input.introMessage || `Happy birthday, ${input.recipientName}! Explore a few favorite places, catch original creatures, and open notes from people who love you.`,
  }).select("id").single();
  if (error) throw new Error(error.message);
  await seedExampleAdventure(supabase, data.id, input.recipientName);
  const { error: publishError } = await supabase.rpc("publish_game", { target_game_id: data.id });
  if (publishError) throw new Error(publishError.message);
  redirect(`/dashboard/games/${data.id}`);
}

export async function seedExampleContent(gameId: string) {
  const { supabase } = await organizer();
  await seedExampleAdventure(supabase, gameId);
  refresh(gameId);
}

async function seedExampleAdventure(
  supabase: Awaited<ReturnType<typeof organizer>>["supabase"],
  gameId: string,
  recipientName = "the birthday star",
) {
  const { count } = await supabase.from("locations").select("id", { count: "exact", head: true })
    .eq("game_id", gameId).neq("state", "archived");
  if ((count ?? 0) > 0) return;

  const { data: places, error: locationError } = await supabase.from("locations").insert([
    {
      game_id: gameId, title: "Hometown Bakery", address: "A favorite pastry shop",
      latitude: 40.73082, longitude: -73.99733, radius_meters: 75,
      hint: "Look for the place that smells like cinnamon.", sort_order: 0, state: "draft",
    },
    {
      game_id: gameId, title: "Riverside Lookout", address: "A quiet view of the water",
      latitude: 40.75364, longitude: -73.98323, radius_meters: 75,
      hint: "Find the open view where you used to people-watch.", sort_order: 1, state: "draft",
    },
    {
      game_id: gameId, title: "Park Bench", address: "The usual meeting spot",
      latitude: 40.78286, longitude: -73.96536, radius_meters: 75,
      hint: "The bench under the big tree.", sort_order: 2, state: "draft",
    },
    {
      game_id: gameId, title: "The office chair", address: "1475 1st Ave, New York, NY 10075",
      latitude: 40.7710274, longitude: -73.9539757, radius_meters: 50,
      hint: "Look for the loaf who claimed the best seat.", sort_order: 10, state: "draft",
    },
    {
      game_id: gameId, title: "The living-room rug", address: "334 E 78th St, New York, NY 10075",
      latitude: 40.7720308, longitude: -73.9543142, radius_meters: 50,
      hint: "Follow the stare from the rug.", sort_order: 11, state: "draft",
    },
  ]).select("id, title");
  if (locationError) throw new Error(locationError.message);
  const bakery = places?.find((place) => place.title === "Hometown Bakery")?.id;
  const lookout = places?.find((place) => place.title === "Riverside Lookout")?.id;
  const bench = places?.find((place) => place.title === "Park Bench")?.id;
  const chair = places?.find((place) => place.title === "The office chair")?.id;
  const rug = places?.find((place) => place.title === "The living-room rug")?.id;
  if (!bakery || !lookout || !bench || !chair || !rug) throw new Error("Example places could not be created");

  const fallbacks = [
    [bakery, "bakery"],
    [lookout, "lookout"],
    [bench, "parkbench"],
    [chair, "chaircat"],
    [rug, "rugcat"],
  ] as const;
  for (const [locationId, code] of fallbacks) {
    const { error } = await supabase.rpc("set_location_fallback", {
      target_location_id: locationId, raw_code: code,
    });
    if (error) throw new Error(error.message);
  }

  const { error: characterError } = await supabase.from("characters").insert([
    {
      game_id: gameId, location_id: bakery, name: "Sprinkles", category: "food", rarity: "common",
      description: "A cheerful pastry pal with a sugar-dusted grin.",
      personality: "Generous, giggly, always offering the last bite.",
      special_ability: "Turns any ordinary morning into a celebration.",
      required: true, xp_value: 100, sort_order: 0,
    },
    {
      game_id: gameId, location_id: lookout, name: "Pocket Map", category: "memory", rarity: "rare",
      description: "A folded creature made of ticket stubs and old photos.",
      personality: "Nostalgic, gentle, remembers every detour.",
      special_ability: "Shows you a shortcut back to a happy day.",
      required: true, xp_value: 150, sort_order: 1,
    },
    {
      game_id: gameId, location_id: bench, name: "The Last Candle", category: "legendary", rarity: "legendary",
      description: "A tiny legendary glow that only appears for one person a year.",
      personality: "Warm, quiet, a little dramatic.",
      special_ability: "Makes a wish feel close enough to hold.",
      required: false, xp_value: 250, sort_order: 2,
    },
    {
      game_id: gameId, location_id: chair, name: "Chair Cat", category: "friend", rarity: "common",
      description: "A professional napper who has mastered the art of occupying office chairs. Rarely moves, but always watches.",
      personality: "Still, loyal, and quietly in charge of the chair.",
      special_ability: "Perfect Loaf",
      required: false, xp_value: 324, sort_order: 10,
    },
    {
      game_id: gameId, location_id: rug, name: "Rug Cat", category: "inside_joke", rarity: "rare",
      description: "A mischievous rug guardian who loves attention and has perfected the dramatic over-the-shoulder stare.",
      personality: "Dramatic, social, and always angling for one more treat.",
      special_ability: "Treat Magnet",
      required: false, xp_value: 512, sort_order: 11,
    },
  ]);
  if (characterError) throw new Error(characterError.message);

  const { error: messageError } = await supabase.from("friend_messages").insert([
    {
      game_id: gameId, sender_name: "A friend", title: "Open this first",
      body: `Happy birthday, ${recipientName}! This note is unlocked right away. The rest of the adventure is waiting on the map.`,
      visibility: "immediate", unlock_type: "immediate", required: true, xp_value: 50, sort_order: 0,
      locked_hint: "A birthday wish is ready to open.",
    },
    {
      game_id: gameId, location_id: lookout, sender_name: "Someone who knows you",
      title: "A note at the lookout",
      body: "Remember this view? We always said we would come back. Today you did.",
      visibility: "location_locked", unlock_type: "location", required: false, xp_value: 50, sort_order: 1,
      locked_hint: "Visit the lookout to unseal this note.",
    },
  ]);
  if (messageError) throw new Error(messageError.message);

  const { error: landmarkError } = await supabase.from("landmarks").insert({
    game_id: gameId, location_id: bench, title: "The meeting tree",
    description: "A quiet landmark for a shared memory.",
    story: "This is where the adventure can slow down for a minute.",
    required: false, xp_value: 75, sort_order: 0,
  });
  if (landmarkError) throw new Error(landmarkError.message);

  const { error: finaleError } = await supabase.from("games").update({
    finale_title: "You found the last surprise",
    finale_letter: `You did it, ${recipientName}. The map, the creatures, and the notes were all for this moment. Replay this screen anytime — the adventure stays yours.`,
    finale_destination: "Wherever you want cake",
  }).eq("id", gameId);
  if (finaleError) throw new Error(finaleError.message);
  await upsertBirthdayCheckpoints(supabase, gameId);
}

export async function updateGame(gameId: string, formData: FormData) {
  const launchRaw = String(formData.get("launchAt") ?? "").trim();
  const { supabase } = await organizer();
  const { error } = await supabase.from("games").update({
    title: required(formData, "title", 100),
    recipient_name: required(formData, "recipientName", 80),
    intro_message: optional(formData, "introMessage", 2000) ?? "",
    launch_at: launchRaw ? new Date(launchRaw).toISOString() : null,
  }).eq("id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function seedAdventureCheckpoints(gameId: string) {
  const { supabase } = await organizer();
  await upsertBirthdayCheckpoints(supabase, gameId);
  refresh(gameId);
}

async function upsertBirthdayCheckpoints(
  supabase: Awaited<ReturnType<typeof organizer>>["supabase"],
  gameId: string,
) {
  const checkpoints = [
    { title: "Grand Central Terminal", address: "Grand Central Terminal, New York, NY", latitude: 40.752726, longitude: -73.977229, hint: "Meet under the constellation ceiling, then spin the memory disc.", fallback: "grandcentral", sort: 20 },
    { title: "Penn Station", address: "Moynihan Train Hall, New York, NY", latitude: 40.750580, longitude: -73.993584, hint: "A wild Anya appeared between the concourse crowds.", fallback: "pennstation", sort: 21 },
    { title: "NYRR RUNCENTER", address: "NYRR RUNCENTER, 320 W 57th St, New York, NY", latitude: 40.76694, longitude: -73.98300, hint: "Grab a bib and remember the start-line butterflies.", fallback: "runcenter", sort: 22 },
    { title: "Chip City Rockefeller", address: "30 Rockefeller Plaza, New York, NY", latitude: 40.758740, longitude: -73.978674, hint: "A concourse cookie is on the loose under the plaza.", fallback: "chiprock", sort: 23 },
    { title: "Chip City Chelsea", address: "Chip City, 272 7th Ave, New York, NY", latitude: 40.74579, longitude: -73.99477, hint: "Chelsea’s cookie counter has a quieter birthday treat.", fallback: "chipchelsea", sort: 24 },
    { title: "Williamsburg", address: "McCarren Park, Brooklyn, NY", latitude: 40.72148, longitude: -73.95236, hint: "A pair of Chrises is holding court near the park paths.", fallback: "williamsburg", sort: 25 },
    { title: "Upper East Side", address: "John Jay Park, New York, NY", latitude: 40.77203, longitude: -73.95431, hint: "Joey is nearby, somewhere a friend would actually wait.", fallback: "uppereast", sort: 26 },
  ];
  const { data: existing } = await supabase.from("locations").select("id, title").eq("game_id", gameId).neq("state", "archived");
  const byTitle = new Map((existing ?? []).map((row) => [row.title, row.id]));
  for (const place of checkpoints) {
    let locationId = byTitle.get(place.title);
    if (!locationId && place.title === "Upper East Side") {
      locationId = byTitle.get("The living-room rug");
    }
    if (!locationId) {
      const { data, error } = await supabase.from("locations").insert({
        game_id: gameId, title: place.title, address: place.address,
        latitude: place.latitude, longitude: place.longitude, radius_meters: 75,
        hint: place.hint, sort_order: place.sort, state: "draft",
      }).select("id").single();
      if (error) throw new Error(error.message);
      locationId = data.id;
    } else {
      await supabase.from("locations").update({
        title: place.title, address: place.address, latitude: place.latitude, longitude: place.longitude,
        radius_meters: 75, hint: place.hint,
      }).eq("id", locationId);
    }
    await supabase.rpc("set_location_fallback", { target_location_id: locationId, raw_code: place.fallback });
  }

  const { data: places } = await supabase.from("locations").select("id, title").eq("game_id", gameId);
  const loc = (title: string) => places?.find((row) => row.title === title)?.id
    ?? (title === "Upper East Side" ? places?.find((row) => row.title === "The living-room rug")?.id : undefined);
  const { data: existingCharacters } = await supabase.from("characters").select("name").eq("game_id", gameId);
  const names = new Set((existingCharacters ?? []).map((row) => row.name));
  const characterRows = [
    loc("Grand Central Terminal") && !names.has("LIRR Train") && { game_id: gameId, location_id: loc("Grand Central Terminal"), name: "LIRR Train", category: "memory", rarity: "rare", description: "A gleaming commuter companion who knows every platform announcement by heart.", personality: "Punctual, proud, a little loud in tunnels.", special_ability: "On-Time Arrival", required: false, xp_value: 0, sort_order: 20 },
    loc("Penn Station") && !names.has("Confused Anya") && { game_id: gameId, location_id: loc("Penn Station"), name: "Confused Anya", category: "inside_joke", rarity: "rare", description: "Always one hallway from the right track, never short on stories.", personality: "Lost, laughing, somehow still on time.", special_ability: "Wrong Staircase", required: false, xp_value: 150, sort_order: 21 },
    loc("Chip City Rockefeller") && !names.has("Rockefeller Cookie") && { game_id: gameId, location_id: loc("Chip City Rockefeller"), name: "Rockefeller Cookie", category: "food", rarity: "common", description: "A plaza cookie who thinks every elevator is a oven timer.", personality: "Gooey, optimistic, slightly famous.", special_ability: "Warm Batch", required: false, xp_value: 100, sort_order: 23 },
    loc("Williamsburg") && !names.has("Chris One") && { game_id: gameId, location_id: loc("Williamsburg"), name: "Chris One", category: "friend", rarity: "rare", description: "Half of a legendary duo. Shows up early and claims the good bench.", personality: "Warm, competitive about snacks.", special_ability: "Plus One", required: false, xp_value: 100, sort_order: 25 },
    loc("Williamsburg") && !names.has("Chris Two") && { game_id: gameId, location_id: loc("Williamsburg"), name: "Chris Two", category: "friend", rarity: "rare", description: "The other half. Arrives fashionably and finishes the story.", personality: "Witty, loyal, never travels alone.", special_ability: "Also Plus One", required: false, xp_value: 100, sort_order: 26 },
    loc("Upper East Side") && !names.has("Joey") && { game_id: gameId, location_id: loc("Upper East Side"), name: "Joey", category: "friend", rarity: "rare", description: "A UES regular who always knows the next good stop on the block.", personality: "Easygoing, funny, first to buy a snack for the table.", special_ability: "Neighborhood Radar", required: false, xp_value: 150, sort_order: 27 },
  ].filter(Boolean);
  if (characterRows.length) {
    const { error } = await supabase.from("characters").insert(characterRows);
    if (error) throw new Error(error.message);
  }

  const { data: existingLandmarks } = await supabase.from("landmarks").select("title").eq("game_id", gameId);
  const landmarkTitles = new Set((existingLandmarks ?? []).map((row) => row.title));
  const landmarkRows = [
    loc("Grand Central Terminal") && !landmarkTitles.has("Grand Central Terminal") && { game_id: gameId, location_id: loc("Grand Central Terminal"), title: "Grand Central Terminal", description: "Spin the memory disc under the stars.", story: "The next train is yours.", required: false, xp_value: 100, sort_order: 20 },
    loc("NYRR RUNCENTER") && !landmarkTitles.has("NYRR RUNCENTER") && { game_id: gameId, location_id: loc("NYRR RUNCENTER"), title: "NYRR RUNCENTER", description: "Collect a race bib.", story: "Pin it on.", required: false, xp_value: 100, sort_order: 22 },
    loc("Chip City Chelsea") && !landmarkTitles.has("Chip City Chelsea") && { game_id: gameId, location_id: loc("Chip City Chelsea"), title: "Chip City Chelsea", description: "A Chelsea-only cookie keepsake.", story: "Different shop, different tin.", required: false, xp_value: 75, sort_order: 24 },
  ].filter(Boolean);
  if (landmarkRows.length) {
    const { error } = await supabase.from("landmarks").insert(landmarkRows);
    if (error) throw new Error(error.message);
  }
}

export async function updateLocation(gameId: string, locationId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("locations").update({
    title: required(formData, "title", 120),
    address: optional(formData, "address", 500),
    hint: optional(formData, "hint", 500),
    latitude: number(formData, "latitude", -90, 90),
    longitude: number(formData, "longitude", -180, 180),
    radius_meters: number(formData, "radius", 10, 10000),
  }).eq("id", locationId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function updateCharacter(gameId: string, characterId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("characters").update({
    name: required(formData, "name", 100),
    description: required(formData, "description", 3000),
    personality: optional(formData, "personality", 1000) ?? "",
    special_ability: optional(formData, "specialAbility", 1000) ?? "",
    xp_value: number(formData, "xp", 0, 10000),
  }).eq("id", characterId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function updateMessage(gameId: string, messageId: string, formData: FormData) {
  const { supabase } = await organizer();
  const fields = messageFields(formData);
  const { error } = await supabase.from("friend_messages").update(fields).eq("id", messageId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  await attachMessageMedia(supabase, gameId, messageId, formData);
  refresh(gameId);
}

export async function publishMessage(gameId: string, messageId: string) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("friend_messages").update({ state: "published" }).eq("id", messageId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function updateLandmark(gameId: string, landmarkId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("landmarks").update({
    title: required(formData, "title", 120),
    description: required(formData, "description", 3000),
    story: optional(formData, "story", 5000),
    xp_value: number(formData, "xp", 0, 10000),
  }).eq("id", landmarkId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function createLocation(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("locations").insert({
    game_id: gameId,
    title: required(formData, "title", 120),
    address: optional(formData, "address", 500),
    latitude: number(formData, "latitude", -90, 90),
    longitude: number(formData, "longitude", -180, 180),
    radius_meters: number(formData, "radius", 10, 10000),
    hint: optional(formData, "hint", 500),
  });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function setLocationFallback(gameId: string, locationId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.rpc("set_location_fallback", {
    target_location_id: locationId,
    raw_code: required(formData, "fallbackCode", 32),
  });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function createCharacter(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const rarity = required(formData, "rarity", 20);
  const defaultXp = rarity === "legendary" ? 250 : rarity === "rare" ? 150 : 100;
  const { data, error } = await supabase.from("characters").insert({
    game_id: gameId,
    location_id: required(formData, "locationId", 36),
    name: required(formData, "name", 100),
    category: required(formData, "category", 20),
    rarity,
    description: required(formData, "description", 3000),
    personality: optional(formData, "personality", 1000) ?? "",
    special_ability: optional(formData, "specialAbility", 1000) ?? "",
    required: formData.get("required") === "on",
    xp_value: defaultXp,
  }).select("id").single();
  if (error) throw new Error(error.message);
  const artwork = formData.get("artwork");
  if (artwork instanceof File && artwork.size > 0) {
    await storePublicImage(supabase, gameId, `characters/${data.id}`, artwork, async (path) => {
      const { error: updateError } = await supabase.from("characters").update({ artwork_path: path }).eq("id", data.id);
      if (updateError) throw new Error(updateError.message);
    });
  }
  refresh(gameId);
}

export async function uploadCharacterArtwork(gameId: string, characterId: string, formData: FormData) {
  const { supabase } = await organizer();
  const artwork = formData.get("artwork");
  if (!(artwork instanceof File) || artwork.size === 0) throw new Error("Artwork is required");
  await storePublicImage(supabase, gameId, `characters/${characterId}`, artwork, async (path) => {
    const { error } = await supabase.from("characters").update({ artwork_path: path }).eq("id", characterId);
    if (error) throw new Error(error.message);
  });
  refresh(gameId);
}

export async function createMessage(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const fields = messageFields(formData);
  const { data, error } = await supabase.from("friend_messages").insert({
    game_id: gameId,
    ...fields,
    state: formData.get("publish") === "on" ? "published" : "draft",
  }).select("id").single();
  if (error) throw new Error(error.message);
  await attachMessageMedia(supabase, gameId, data.id, formData);
  refresh(gameId);
}

export async function createLandmark(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { data, error } = await supabase.from("landmarks").insert({
    game_id: gameId,
    location_id: required(formData, "locationId", 36),
    title: required(formData, "title", 120),
    description: required(formData, "description", 3000),
    story: optional(formData, "story", 5000),
    required: formData.get("required") === "on",
  }).select("id").single();
  if (error) throw new Error(error.message);
  const image = formData.get("image");
  if (image instanceof File && image.size > 0) {
    await storePublicImage(supabase, gameId, `landmarks/${data.id}`, image, async (path) => {
      const { error: updateError } = await supabase.from("landmarks").update({ image_path: path }).eq("id", data.id);
      if (updateError) throw new Error(updateError.message);
    });
  }
  refresh(gameId);
}

export async function saveFinale(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("games").update({
    finale_title: required(formData, "title", 120),
    finale_letter: required(formData, "letter", 10000),
    finale_destination: optional(formData, "destination", 500),
  }).eq("id", gameId);
  if (error) throw new Error(error.message);
  const media = formData.get("media");
  if (media instanceof File && media.size > 0) {
    await storePrivateFile(supabase, gameId, `finale/${gameId}`, media, async (path) => {
      const { error: updateError } = await supabase.from("games").update({ finale_media_path: path }).eq("id", gameId);
      if (updateError) throw new Error(updateError.message);
    });
  }
  refresh(gameId);
}

export async function uploadCoverArt(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const cover = formData.get("cover");
  if (!(cover instanceof File) || cover.size === 0) throw new Error("Cover artwork is required");
  await storePublicImage(supabase, gameId, "cover", cover, async (path) => {
    const { error } = await supabase.from("games").update({ cover_art_path: path }).eq("id", gameId);
    if (error) throw new Error(error.message);
  });
  refresh(gameId);
}

export async function archiveContent(gameId: string, table: string, id: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.rpc("archive_game_content", {
    target_game_id: gameId,
    target_table: table,
    target_id: id,
    confirmation: String(formData.get("confirmation") ?? ""),
  });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function publishGame(gameId: string) {
  const { supabase } = await organizer();
  const { error } = await supabase.rpc("publish_game", { target_game_id: gameId });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function unpublishGame(gameId: string, formData: FormData) {
  if (String(formData.get("confirmation") ?? "") !== "UNPUBLISH") {
    throw new Error("Type UNPUBLISH to confirm.");
  }
  const { supabase } = await organizer();
  const { error } = await supabase.from("games").update({ state: "draft" }).eq("id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function moderateSubmission(gameId: string, submissionId: string, decision: "approved" | "rejected") {
  const { supabase, user } = await organizer();
  const { data: submission, error: readError } = await supabase.from("submissions")
    .select("*, submission_media(*)").eq("id", submissionId).eq("game_id", gameId).single();
  if (readError) throw new Error(readError.message);
  if (decision === "approved") {
    const { data: message, error } = await supabase.from("friend_messages").insert({
      game_id: gameId, sender_name: submission.display_name, body: submission.message,
      title: `A note from ${submission.display_name}`, visibility: "immediate", state: "draft",
      unlock_type: "immediate", unlock_rule: "all",
      locked_hint: submission.memory_suggestion || submission.location_suggestion || "A birthday wish from a friend.",
    }).select("id").single();
    if (error) throw new Error(error.message);
    const media = submission.submission_media ?? [];
    for (const item of media) {
      const { data: file, error: downloadError } = await supabase.storage
        .from("submission-quarantine").download(item.storage_path);
      if (downloadError) throw new Error(downloadError.message);
      const dest = `${gameId}/messages/${message.id}/${item.id}`;
      const { error: uploadError } = await supabase.storage.from("private-media")
        .upload(dest, file, { contentType: item.mime_type, upsert: false });
      if (uploadError) throw new Error(uploadError.message);
      const { error: mediaError } = await supabase.from("message_media").insert({
        message_id: message.id,
        kind: item.kind,
        storage_path: dest,
        mime_type: item.mime_type,
        byte_size: item.byte_size,
        duration_seconds: item.duration_seconds,
      });
      if (mediaError) throw new Error(mediaError.message);
    }
  }
  const { error } = await supabase.from("submissions").update({
    status: decision, reviewed_by: user.id, reviewed_at: new Date().toISOString(),
  }).eq("id", submissionId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function createEggType(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const rarities = formData.getAll("rarities").map(String).filter((value) => ["common", "rare", "legendary"].includes(value));
  const { error } = await supabase.from("egg_types").insert({
    game_id: gameId,
    type_key: required(formData, "typeKey", 40),
    title: required(formData, "title", 80),
    required_meters: number(formData, "requiredMeters", 100, 200000),
    xp_value: number(formData, "xp", 0, 10000),
    artwork_style: required(formData, "artworkStyle", 12),
    rarity_label: required(formData, "rarityLabel", 80),
    allowed_rarities: rarities.length ? rarities : ["common", "rare"],
    exclude_duplicates: formData.get("excludeDuplicates") === "on",
    duplicate_xp: number(formData, "duplicateXp", 0, 10000),
  });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function updateEggType(gameId: string, eggTypeId: string, formData: FormData) {
  const { supabase } = await organizer();
  const rarities = formData.getAll("rarities").map(String).filter((value) => ["common", "rare", "legendary"].includes(value));
  const { error } = await supabase.from("egg_types").update({
    title: required(formData, "title", 80),
    required_meters: number(formData, "requiredMeters", 100, 200000),
    xp_value: number(formData, "xp", 0, 10000),
    artwork_style: required(formData, "artworkStyle", 12),
    rarity_label: required(formData, "rarityLabel", 80),
    allowed_rarities: rarities.length ? rarities : ["common", "rare"],
    exclude_duplicates: formData.get("excludeDuplicates") === "on",
    duplicate_xp: number(formData, "duplicateXp", 0, 10000),
  }).eq("id", eggTypeId).eq("game_id", gameId);
  if (error) throw new Error(error.message);
  const artwork = formData.get("artwork");
  if (artwork instanceof File && artwork.size > 0) {
    await storePublicImage(supabase, gameId, `eggs/${eggTypeId}`, artwork, async (path) => {
      const { error: artError } = await supabase.from("egg_types").update({ artwork_path: path }).eq("id", eggTypeId);
      if (artError) throw new Error(artError.message);
    });
  }
  refresh(gameId);
}

export async function saveEggRewards(gameId: string, eggTypeId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error: clearError } = await supabase.from("egg_type_rewards").delete().eq("egg_type_id", eggTypeId);
  if (clearError) throw new Error(clearError.message);
  const selected = formData.getAll("characterId").map(String).filter(Boolean);
  if (selected.length) {
    const rows = selected.map((characterId) => ({
      egg_type_id: eggTypeId,
      character_id: characterId,
      weight: Number(formData.get(`weight-${characterId}`)) || 1,
    }));
    const { error } = await supabase.from("egg_type_rewards").insert(rows);
    if (error) throw new Error(error.message);
  }
  refresh(gameId);
}

export async function grantPlayerEgg(gameId: string, formData: FormData) {
  const { supabase } = await organizer();
  const { error } = await supabase.rpc("grant_player_egg", {
    target_game_id: gameId,
    target_player_id: required(formData, "playerId", 36),
    target_egg_type_id: required(formData, "eggTypeId", 36),
    test_grant: formData.get("isTest") === "on",
  });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function resetTestEggs(gameId: string) {
  const { supabase } = await organizer();
  const { error } = await supabase.rpc("reset_test_eggs", { target_game_id: gameId });
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function revokeDevice(gameId: string, deviceId: string) {
  const { supabase } = await organizer();
  const { error } = await supabase.from("player_devices").update({ revoked_at: new Date().toISOString() }).eq("id", deviceId);
  if (error) throw new Error(error.message);
  refresh(gameId);
}

export async function createInvite(gameId: string, kind: "player" | "contributor") {
  const { supabase } = await organizer();
  const { data, error } = await supabase.rpc("create_scoped_invitation", {
    target_game_id: gameId,
    invitation_type: kind,
    validity: kind === "player" ? "30 days" : "60 days",
    allowed_uses: kind === "player" ? 1 : 50,
  });
  if (error) throw new Error(error.message);
  redirect(`/dashboard/games/${gameId}?invite=${encodeURIComponent(data)}&kind=${kind}`);
}

export async function createRecovery(gameId: string) {
  const { supabase } = await organizer();
  const { data, error } = await supabase.rpc("create_player_recovery", {
    target_game_id: gameId,
    validity: "24 hours",
  });
  if (error) throw new Error(error.message);
  redirect(`/dashboard/games/${gameId}?invite=${encodeURIComponent(data)}&kind=recovery`);
}

async function storePublicImage(
  supabase: Awaited<ReturnType<typeof organizer>>["supabase"],
  gameId: string,
  key: string,
  file: File,
  save: (path: string) => Promise<void>,
) {
  assertImage(file);
  const path = `${gameId}/${key}.${extensionFor(file.type)}`;
  const { error } = await supabase.storage.from("public-artwork").upload(path, file, { upsert: true, contentType: file.type });
  if (error) throw new Error(error.message);
  await save(path);
}

async function storePrivateFile(
  supabase: Awaited<ReturnType<typeof organizer>>["supabase"],
  gameId: string,
  key: string,
  file: File,
  save: (path: string) => Promise<void>,
) {
  if (file.size > 26_214_400) throw new Error("File is too large");
  const allowed = ["image/jpeg", "image/png", "image/webp", "video/mp4", "audio/mpeg", "audio/mp4", "audio/x-m4a"];
  if (!allowed.includes(file.type)) throw new Error("Unsupported file type");
  const path = `${gameId}/${key}.${extensionFor(file.type)}`;
  const { error } = await supabase.storage.from("private-media").upload(path, file, { upsert: true, contentType: file.type });
  if (error) throw new Error(error.message);
  await save(path);
}

function assertImage(file: File) {
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type) || file.size > 10_485_760) {
    throw new Error("Artwork must be JPG, PNG, or WebP under 10 MB");
  }
}

function extensionFor(type: string) {
  if (type === "image/png") return "png";
  if (type === "image/webp") return "webp";
  if (type === "video/mp4") return "mp4";
  if (type === "audio/mpeg") return "mp3";
  if (type === "audio/mp4" || type === "audio/x-m4a") return "m4a";
  return "jpg";
}

function messageFields(form: FormData) {
  const unlockType = required(form, "unlockType", 20);
  if (!["immediate", "location", "character", "passport", "composite"].includes(unlockType)) {
    throw new Error("Invalid unlock type");
  }
  const locationId = optional(form, "locationId", 36);
  const characterId = optional(form, "characterId", 36);
  const stamp = optional(form, "passportStampKey", 80);
  if (unlockType === "location" && !locationId) throw new Error("Location is required for location unlocks");
  if (unlockType === "character" && !characterId) throw new Error("Character is required for character unlocks");
  if (unlockType === "passport" && !stamp) throw new Error("Passport stamp is required for passport unlocks");
  const unlockRule = optional(form, "unlockRule", 8) ?? "all";
  if (unlockRule !== "all" && unlockRule !== "any") throw new Error("Unlock rule must be ALL or ANY");
  return {
    sender_name: required(form, "senderName", 80),
    title: required(form, "title", 120),
    body: required(form, "body", 5000),
    visibility: unlockType === "immediate" ? "immediate" : "location_locked",
    location_id: locationId,
    character_id: characterId,
    passport_stamp_key: stamp,
    unlock_type: unlockType,
    unlock_rule: unlockRule,
    locked_hint: optional(form, "lockedHint", 240),
    reveal_sender_when_locked: form.get("revealSender") === "on",
    required: form.get("required") === "on",
    xp_value: Number.isFinite(Number(form.get("xp"))) ? number(form, "xp", 0, 10000) : 25,
  };
}

async function attachMessageMedia(
  supabase: Awaited<ReturnType<typeof organizer>>["supabase"],
  gameId: string,
  messageId: string,
  formData: FormData,
) {
  const photo = formData.get("photo");
  if (photo instanceof File && photo.size > 0) {
    await storePrivateFile(supabase, gameId, `messages/${messageId}/photo`, photo, async (path) => {
      const { error } = await supabase.from("message_media").insert({
        message_id: messageId, kind: "image", storage_path: path, mime_type: photo.type, byte_size: photo.size,
      });
      if (error) throw new Error(error.message);
    });
  }
  const audio = formData.get("audio");
  if (audio instanceof File && audio.size > 0) {
    await storePrivateFile(supabase, gameId, `messages/${messageId}/audio`, audio, async (path) => {
      const { error } = await supabase.from("message_media").insert({
        message_id: messageId, kind: "audio", storage_path: path, mime_type: audio.type, byte_size: audio.size,
        duration_seconds: Number(formData.get("durationSeconds")) || null,
      });
      if (error) throw new Error(error.message);
    });
  }
  const senderPhoto = formData.get("senderPhoto");
  if (senderPhoto instanceof File && senderPhoto.size > 0) {
    await storePrivateFile(supabase, gameId, `messages/${messageId}/sender`, senderPhoto, async (path) => {
      const { error } = await supabase.from("friend_messages").update({ sender_photo_path: path }).eq("id", messageId);
      if (error) throw new Error(error.message);
    });
  }
}

function required(form: FormData, name: string, max: number) {
  const value = String(form.get(name) ?? "").trim();
  if (!value || value.length > max) throw new Error(`Invalid ${name}`);
  return value;
}
function optional(form: FormData, name: string, max: number) {
  const value = String(form.get(name) ?? "").trim();
  if (value.length > max) throw new Error(`Invalid ${name}`);
  return value || null;
}
function number(form: FormData, name: string, min: number, max: number) {
  const value = Number(form.get(name));
  if (!Number.isFinite(value) || value < min || value > max) throw new Error(`Invalid ${name}`);
  return value;
}
