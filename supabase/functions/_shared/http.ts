import { createClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "access-control-allow-origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-player-token, x-installation-id",
  "access-control-allow-methods": "POST, OPTIONS",
};

export function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Server configuration is incomplete");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export function json(body: unknown, status = 200, headers: HeadersInit = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json", ...headers },
  });
}

export function safeError(error: unknown) {
  const message = error instanceof Error ? error.message : "request_failed";
  const known = [
    "invalid_invitation", "invalid_recovery", "game_unavailable", "unauthorized", "device_revoked",
    "invalid_installation_id",
    "rate_limited", "location_inaccurate", "location_required", "dwell_required", "outside_radius",
    "content_unavailable", "invalid_content_kind", "not_launched", "consent_required",
  ];
  const code = known.find((candidate) => message.includes(candidate)) ?? "request_failed";
  const status = code === "rate_limited" ? 429 : code === "unauthorized" || code === "device_revoked" ? 401 : 400;
  return json({ error: code }, status);
}

export function requireString(value: unknown, name: string, max = 5000) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > max) {
    throw new Error(`invalid_${name}`);
  }
  return value.trim();
}

export async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return `\\x${Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

export function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
