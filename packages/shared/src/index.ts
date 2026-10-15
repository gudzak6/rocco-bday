import { z } from "zod";

export const UUID = z.string().uuid();
export const PublicationState = z.enum(["draft", "published", "archived"]);
export const Rarity = z.enum(["common", "rare", "legendary"]);
export const CharacterCategory = z.enum([
  "friend",
  "food",
  "memory",
  "inside_joke",
  "legendary",
]);

export const GameInput = z.object({
  title: z.string().trim().min(1).max(100),
  recipientName: z.string().trim().min(1).max(80),
  introMessage: z.string().trim().max(2000).default(""),
  launchAt: z.string().datetime().nullable().default(null),
});

export const SubmissionInput = z.object({
  invitationToken: z.string().min(32).max(512),
  displayName: z.string().trim().min(1).max(80),
  message: z.string().trim().min(1).max(5000),
  memorySuggestion: z.string().trim().max(2000).optional(),
  locationSuggestion: z.string().trim().max(500).optional(),
  characterIdea: z.string().trim().max(1000).optional(),
  consent: z.literal(true),
  website: z.string().max(0).optional(),
});

export const RedeemInput = z.object({
  invitationToken: z.string().min(32).max(512),
  deviceName: z.string().trim().min(1).max(120),
  installationId: UUID,
});

export const ProximityInput = z.object({
  contentType: z.enum(["character", "message", "landmark"]),
  contentId: UUID,
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  horizontalAccuracy: z.number().positive().max(1000),
  dwellStartedAt: z.string().datetime(),
  idempotencyKey: UUID,
  fallbackCode: z.string().trim().min(6).max(32).optional(),
});

export type GameInput = z.infer<typeof GameInput>;
export type SubmissionInput = z.infer<typeof SubmissionInput>;
export type RedeemInput = z.infer<typeof RedeemInput>;
export type ProximityInput = z.infer<typeof ProximityInput>;
