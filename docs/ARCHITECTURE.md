# Birthday GO architecture

## Trust boundaries

- **iOS recipient app:** stores the opaque player access token in Keychain. It receives published map metadata, but private note bodies and media only after a server-confirmed unlock.
- **Organizer portal:** uses Supabase Auth and the caller's JWT. PostgreSQL RLS limits every operation to games owned by that organizer.
- **Contributor portal:** has no account. An expiring, revocable invitation secret is exchanged with an Edge Function; only a SHA-256 digest is stored.
- **Supabase:** PostgreSQL is the source of truth. Security-definer RPCs and Edge Functions atomically validate proximity/fallback codes, grant content, and insert unique reward-ledger entries.
- **Storage:** all user media is private. Authorized server operations issue short-lived signed URLs. Public artwork can use a separate public bucket after moderation.

GPS is treated as a useful signal, not fraud-proof evidence. Unlock requests include a current coordinate, horizontal accuracy, and dwell samples. The server checks accuracy, distance, timing, rate limits, and grossly implausible movement, then discards request coordinates after authorization; no location trail is retained.

## Monorepo

```text
apps/
  admin/                 Next.js organizer and contributor portal
  ios/BirthdayGO/        SwiftUI app, XcodeGen project spec, tests
packages/
  shared/                TypeScript contracts and validation schemas
supabase/
  migrations/            schema, constraints, RLS, storage, RPCs
  functions/             Deno Edge Functions
  tests/                 SQL/RLS integration tests
docs/                    setup, privacy, operations, test and release guides
```

## Core workflows

1. Organizer signs in, creates a draft game and content, validates it, then publishes.
2. Contributor submits through a scoped invitation; uploads are quarantined and the submission remains pending.
3. The iPhone app joins the latest published open-play adventure automatically. A private invitation remains optional. The backend creates a player identity/device session and returns only the player token.
4. The app syncs published map metadata. Proximity requests are authorized server-side. Captures map to the `capture` reward source; notes and landmarks use their own sources. Rewards use idempotency keys and database uniqueness constraints.
5. Immediate notes skip GPS. Location-locked content requires accuracy, dwell, radius, or a hashed fallback code.
6. Server completion logic unlocks the finale once all required published items are completed. Optional content never blocks completion.

## Offline model

SwiftData caches public published metadata and decrypted, already-unlocked content. Pending mutations carry stable UUID idempotency keys. Locked message bodies and private media are never written to the offline cache before authorization.
