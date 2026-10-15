import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const query = request.nextUrl.searchParams.get("q")?.trim();
  if (!query || query.length > 200) return NextResponse.json({ error: "invalid_query" }, { status: 400 });
  const endpoint = new URL("https://nominatim.openstreetmap.org/search");
  endpoint.searchParams.set("q", query);
  endpoint.searchParams.set("format", "jsonv2");
  endpoint.searchParams.set("limit", "1");
  const response = await fetch(endpoint, {
    headers: { "user-agent": "BirthdayGO/1.0 (organizer address lookup)" },
    next: { revalidate: 86400 },
  });
  if (!response.ok) return NextResponse.json({ error: "lookup_failed" }, { status: 502 });
  const [result] = await response.json() as Array<{ lat: string; lon: string; display_name: string }>;
  if (!result) return NextResponse.json({ error: "not_found" }, { status: 404 });
  return NextResponse.json({
    latitude: Number(result.lat), longitude: Number(result.lon), address: result.display_name,
  });
}
