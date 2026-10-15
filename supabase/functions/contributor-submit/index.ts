import { corsHeaders, json, requireString, safeError, serviceClient, sha256 } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const contentType = request.headers.get("content-type") ?? "";
    const form = contentType.includes("multipart/form-data") ? await request.formData() : null;
    const body = form ? Object.fromEntries(form.entries()) : await request.json();
    if (body.website) return json({ accepted: true });
    if (body.consent !== true && body.consent !== "true") return json({ error: "consent_required" }, 400);

    const token = requireString(body.invitationToken, "invitation_token", 512);
    const displayName = requireString(body.displayName, "display_name", 80);
    const message = requireString(body.message, "message", 5000);
    if (form) {
      for (const [field, allowed, maximum] of [
        ["photo", ["image/jpeg", "image/png", "image/webp"], 10_485_760],
        ["audio", ["audio/mpeg", "audio/mp4", "audio/x-m4a"], 15_728_640],
      ] as const) {
        const file = form.get(field);
        if (file instanceof File && file.size > 0
          && (file.size > maximum || !(allowed as readonly string[]).includes(file.type))) {
          return json({ error: `invalid_${field}` }, 400);
        }
      }
    }
    const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0] ?? "unknown";
    const fingerprint = await sha256(`${Deno.env.get("RATE_LIMIT_SALT") ?? "local"}:${forwarded}`);

    const supabase = serviceClient();
    const { data, error } = await supabase.rpc("create_contribution", {
      invitation_token_digest: await sha256(token),
      contributor_name: displayName,
      birthday_message: message,
      suggested_location: typeof body.locationSuggestion === "string" ? body.locationSuggestion : "",
      suggested_memory: typeof body.memorySuggestion === "string" ? body.memorySuggestion : "",
      suggested_character: typeof body.characterIdea === "string" ? body.characterIdea : "",
      request_fingerprint: fingerprint,
    });
    if (error) throw error;
    if (form) {
      const { data: submission, error: readError } = await supabase.from("submissions")
        .select("game_id").eq("id", data).single();
      if (readError) throw readError;
      for (const [field, kind, allowed, maximum] of [
        ["photo", "image", ["image/jpeg", "image/png", "image/webp"], 10_485_760],
        ["audio", "audio", ["audio/mpeg", "audio/mp4", "audio/x-m4a"], 15_728_640],
      ] as const) {
        const file = form.get(field);
        if (!(file instanceof File) || file.size === 0) continue;
        if (file.size > maximum || !(allowed as readonly string[]).includes(file.type)) {
          return json({ error: `invalid_${field}` }, 400);
        }
        const extension = file.name.split(".").pop()?.replace(/[^a-z0-9]/gi, "").slice(0, 8) || "bin";
        const path = `${submission.game_id}/${data}/${crypto.randomUUID()}.${extension}`;
        const { error: uploadError } = await supabase.storage.from("submission-quarantine")
          .upload(path, file, { contentType: file.type, upsert: false });
        if (uploadError) throw uploadError;
        const duration = field === "audio" && typeof body.durationSeconds === "string"
          ? Number(body.durationSeconds) : null;
        if (duration != null && (!Number.isFinite(duration) || duration > 600)) {
          return json({ error: "invalid_audio" }, 400);
        }
        const { error: mediaError } = await supabase.from("submission_media").insert({
          submission_id: data, kind, storage_path: path, mime_type: file.type, byte_size: file.size,
          duration_seconds: duration != null && duration >= 1 ? Math.round(duration) : null,
        });
        if (mediaError) throw mediaError;
      }
    }
    return json({ accepted: true, submissionId: data }, 201);
  } catch (error) {
    return safeError(error);
  }
});
