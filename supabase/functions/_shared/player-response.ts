import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type PlayerPayload = {
  game?: { coverArtPath?: string | null };
  characters?: Array<{ captured: boolean; artworkPath?: string | null }>;
  landmarks?: Array<{ imagePath?: string | null }>;
  unlockedMessages?: Array<{ media?: Array<{ path: string }>; senderPhotoPath?: string | null }>;
  finale?: { unlocked: boolean; mediaPath?: string | null };
};

function publicArtworkURL(client: SupabaseClient, path: string | null | undefined) {
  if (!path) return path ?? null;
  if (path.startsWith("http://") || path.startsWith("https://") || path.startsWith("file://")) return path;
  return client.storage.from("public-artwork").getPublicUrl(path).data.publicUrl;
}

export async function attachMediaURLs(client: SupabaseClient, payload: PlayerPayload) {
  if (payload.game?.coverArtPath) {
    payload.game.coverArtPath = publicArtworkURL(client, payload.game.coverArtPath);
  }
  for (const message of payload.unlockedMessages ?? []) {
    for (const media of message.media ?? []) {
      if (media.path.startsWith("http://") || media.path.startsWith("https://") || media.path.startsWith("file://")) continue;
      const { data } = await client.storage.from("private-media").createSignedUrl(media.path, 3600);
      media.path = data?.signedUrl ?? "";
    }
    if (message.senderPhotoPath && !message.senderPhotoPath.startsWith("http") && !message.senderPhotoPath.startsWith("file://")) {
      const { data } = await client.storage.from("private-media").createSignedUrl(message.senderPhotoPath, 3600);
      message.senderPhotoPath = data?.signedUrl ?? message.senderPhotoPath;
    }
  }
  if (payload.finale?.unlocked && payload.finale.mediaPath) {
    const path = payload.finale.mediaPath;
    if (!path.startsWith("http://") && !path.startsWith("https://") && !path.startsWith("file://")) {
      const { data } = await client.storage.from("private-media").createSignedUrl(path, 3600);
      payload.finale.mediaPath = data?.signedUrl ?? null;
    }
  }
  for (const character of payload.characters ?? []) {
    if (character.captured && character.artworkPath) {
      character.artworkPath = publicArtworkURL(client, character.artworkPath);
    }
  }
  for (const landmark of payload.landmarks ?? []) {
    if (landmark.imagePath) {
      landmark.imagePath = publicArtworkURL(client, landmark.imagePath);
    }
  }
  return payload;
}
