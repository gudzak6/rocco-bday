import { corsHeaders, json, randomToken, requireString, safeError, serviceClient, sha256 } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const body = await request.json();
    const deviceName = requireString(body.deviceName, "device_name", 120);
    const installationId = requireString(body.installationId, "installation_id", 36);
    if (!/^[0-9a-f-]{36}$/i.test(installationId)) throw new Error("invalid_installation_id");

    const accessToken = randomToken();
    const { data, error } = await serviceClient().rpc("join_open_game", {
      new_access_token_digest: await sha256(accessToken),
      target_installation_id: installationId,
      device_name: deviceName,
    }).single();
    if (error) throw error;

    return json({
      playerId: data.player_id,
      gameId: data.game_id,
      recipientName: data.recipient_name,
      accessToken,
    });
  } catch (error) {
    return safeError(error);
  }
});
