# Operations

Birthday GO is a single-recipient product. Operate it as a private event, not as a public multi-tenant consumer app, unless you later add additional isolation reviews.

## Daily organizer checklist

1. Confirm the game is published only when locations, required characters, notes, landmarks, and the finale letter are ready.
2. Share contributor links individually. Revoke a link from the invitations table if it is forwarded too widely.
3. Review pending submissions before the launch date. Approving creates a draft note; publish the game (or republish) after you are happy with the copy.
4. Set a fallback code on every venue-dependent required stop.
5. After the recipient redeems, watch aggregate XP only. Do not request live GPS.
6. If a phone is lost, revoke the device and issue a recovery code.

## Incident response

- Auth abuse: disable the organizer user in Supabase Auth and rotate the anon/service keys if they leaked.
- Invitation leak: revoke the invitation row (`revoked_at = now()`) and create a new one.
- Bad media: reject the submission, delete the quarantine object, and if it was already approved, archive the resulting note.
- Database: migrations are forward-only. Restore from a backup only with a written incident plan; live captures and unlocks must not be overwritten casually.

## Backups

Enable point-in-time recovery on the hosted Supabase project. Export game JSON from the organizer dashboard before large content edits. Store exports privately; they contain message bodies.

## Monitoring

Edge Function logs show `progress.attempt` audit rows by content ID, not coordinates. Alert on a sudden spike of `rate_limited` or `unauthorized` responses for one token.

## Content deletion

Archive published content instead of deleting it. Hard deletes of characters, notes, or landmarks that already granted XP can leave ledger rows pointing at missing sources. Use the archive confirmation (`ARCHIVE`) in the organizer portal.
