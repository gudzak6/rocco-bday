import { corsHeaders, json, requireString, safeError, serviceClient } from "../_shared/http.ts";
import { attachMediaURLs } from "../_shared/player-response.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const accessToken = request.headers.get("x-player-token");
    const installationId = request.headers.get("x-installation-id");
    if (!accessToken || !installationId) throw new Error("unauthorized");
    const body = await request.json();
    const contentType = requireString(body.contentType, "content_type", 20);
    if (!["character", "message", "landmark"].includes(contentType)) throw new Error("invalid_content_kind");
    for (const field of ["latitude", "longitude", "horizontalAccuracy"]) {
      if (body[field] != null && (typeof body[field] !== "number" || !Number.isFinite(body[field]))) {
        throw new Error(`invalid_${field}`);
      }
    }

    const supabase = serviceClient();
    const { data, error } = await supabase.rpc("authorize_progress", {
      raw_access_token: accessToken,
      target_installation_id: installationId,
      content_kind: contentType,
      content_id: requireString(body.contentId, "content_id", 36),
      sample_latitude: typeof body.latitude === "number" ? body.latitude : null,
      sample_longitude: typeof body.longitude === "number" ? body.longitude : null,
      horizontal_accuracy: typeof body.horizontalAccuracy === "number" ? body.horizontalAccuracy : null,
      dwell_started_at: typeof body.dwellStartedAt === "string" ? body.dwellStartedAt : new Date(0).toISOString(),
      request_id: requireString(body.idempotencyKey ?? body.id, "idempotency_key", 36),
      fallback_code: typeof body.fallbackCode === "string" ? body.fallbackCode : null,
    });
    if (error) throw error;
    return json(await attachMediaURLs(supabase, data), 200, { "cache-control": "private, no-store" });
  } catch (error) {
    return safeError(error);
  }
});
