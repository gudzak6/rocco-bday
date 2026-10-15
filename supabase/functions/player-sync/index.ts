import { corsHeaders, json, safeError, serviceClient } from "../_shared/http.ts";
import { attachMediaURLs } from "../_shared/player-response.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const accessToken = request.headers.get("x-player-token");
    const installationId = request.headers.get("x-installation-id");
    if (!accessToken || !installationId) throw new Error("unauthorized");
    const supabase = serviceClient();
    const body = await request.json().catch(() => ({}));
    if (body && typeof body === "object" && body.resetCollection === true) {
      const { error: resetError } = await supabase.rpc("reset_player_collection", {
        raw_access_token: accessToken,
        target_installation_id: installationId,
      });
      if (resetError) throw resetError;
    }
    if (body && typeof body === "object" && body.avatarStyle && typeof body.avatarStyle === "object") {
      const { error: avatarError } = await supabase.rpc("update_player_avatar", {
        raw_access_token: accessToken,
        target_installation_id: installationId,
        style: body.avatarStyle,
      });
      if (avatarError) throw avatarError;
    }
    const { data, error } = await supabase.rpc("player_bootstrap", {
      raw_access_token: accessToken,
      target_installation_id: installationId,
    });
    if (error) throw error;
    return json(await attachMediaURLs(supabase, data), 200, { "cache-control": "private, no-store" });
  } catch (error) {
    return safeError(error);
  }
});
