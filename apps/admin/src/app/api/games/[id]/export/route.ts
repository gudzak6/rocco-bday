import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: game, error } = await supabase.from("games").select("*").eq("id", id).single();
  if (error) return NextResponse.json({ error: "not_found" }, { status: 404 });
  const [locations, characters, messages, landmarks, submissions] = await Promise.all([
    supabase.from("locations").select("*").eq("game_id", id),
    supabase.from("characters").select("*").eq("game_id", id),
    supabase.from("friend_messages").select("*,message_media(*)").eq("game_id", id),
    supabase.from("landmarks").select("*").eq("game_id", id),
    supabase.from("submissions").select("*,submission_media(*)").eq("game_id", id),
  ]);
  const body = JSON.stringify({
    exportedAt: new Date().toISOString(),
    game,
    locations: locations.data ?? [],
    characters: characters.data ?? [],
    messages: messages.data ?? [],
    landmarks: landmarks.data ?? [],
    submissions: submissions.data ?? [],
  }, null, 2);
  return new NextResponse(body, {
    headers: {
      "content-type": "application/json",
      "content-disposition": `attachment; filename="birthday-go-${id}.json"`,
      "cache-control": "private, no-store",
    },
  });
}
