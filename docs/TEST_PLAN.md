# Test and real-device acceptance plan

## Automated gates

- TypeScript typecheck, ESLint, Vitest contract tests, and Playwright desktop/mobile tests.
- Supabase migration reset and pgTAP RLS/constraint tests.
- Swift unit tests for distance, accuracy, eligibility, decoding, progression state, and completion.
- XCUITests for invitation, permission states, map/list navigation, capture accessibility, memory book, and finale replay.

## Required staging scenarios

1. Organizer creates a game, places a real map pin, adds each content type, configures required content/finale, publishes, and exports the configuration.
2. Friend link accepts valid text/photo/audio, rejects wrong MIME, oversize and audio over 10 minutes, survives a retried upload without auto-publishing, and fails after revoke/expiry.
3. The iPhone app joins the published open-play adventure without an invite code, remains bound after relaunch, and recovers only with an organizer-issued recovery token. Private player invites still redeem once if used.
4. At a real location, inaccurate GPS is rejected; accurate GPS requires dwell; duplicate/replayed requests do not duplicate XP.
5. Denied location still permits the nearby list and fallback code. Test a closed venue using a controlled fallback.
6. Airplane mode preserves previously unlocked text/media, never reveals locked bodies, queues a stable progress operation, and reconciles after reconnect.
7. Force-quit during server-authorized capture, relaunch, and confirm the capture is present exactly once.
8. Revoke a device and confirm sync/progress return unauthorized.
9. Complete all required content while leaving optional content undone; verify finale unlock, 500 XP once, and permanent replay.
10. Test VoiceOver order/labels, Dynamic Type through accessibility sizes, Reduce Motion, color contrast, and tap-to-catch.

## Device matrix

- Smallest supported iPhone and current large iPhone on iOS 17 and latest iOS.
- Slow/reliable Wi-Fi, cellular, offline, interrupted upload, low-storage, and app termination.
- Fresh install, upgrade over previous build, timezone change, and launch before configured date.

Record device/OS/build, tester, timestamp, expected/actual result, screenshots, and backend audit event IDs for every release candidate.
