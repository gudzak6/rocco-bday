# Birthday GO

Birthday GO is a private, location-based birthday adventure: a native SwiftUI player app, a Next.js organizer/contributor portal, and a Supabase authorization backend.

## Quick start

Prerequisites: Node 20+, pnpm 10+, Docker, Supabase CLI, Xcode 26+, and XcodeGen.

```bash
pnpm install
cp apps/admin/.env.example apps/admin/.env.local
npx supabase start
npx supabase db reset
npx supabase functions serve --env-file supabase/.env.local
pnpm dev
```

Generate and open the iOS project:

```bash
cd apps/ios/BirthdayGO
xcodegen generate
open BirthdayGO.xcodeproj
```

Set `BG_API_BASE_URL` in the BirthdayGO target build settings to the hosted functions URL, for example:

`https://ookqnalokcpqvdojmcmy.supabase.co/functions/v1/`

For local Edge Functions, use `http://127.0.0.1:54321/functions/v1/` in the simulator only.

Set a unique production bundle identifier and Apple development team before signing.

## Verification

```bash
pnpm typecheck
pnpm lint
pnpm test
npx supabase db test
xcodebuild test -project apps/ios/BirthdayGO/BirthdayGO.xcodeproj \
  -scheme BirthdayGO -destination 'platform=iOS Simulator,name=iPhone 17'
```

No production birthday content or credentials are committed. Organizer users must be created by invitation in Supabase Auth because public signup is disabled.

See [architecture](docs/ARCHITECTURE.md), [setup and deployment](docs/DEPLOYMENT.md), [privacy](docs/PRIVACY.md), and [test plan](docs/TEST_PLAN.md).
