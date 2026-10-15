# Setup and deployment

## Supabase

1. Create separate staging and production projects.
2. Link the CLI and run `supabase db push`.
3. Deploy `player-join`, `player-redeem`, `player-sync`, `player-progress`, `player-recover`, and `contributor-submit`.
4. Set `ALLOWED_ORIGIN` to the exact portal origin and set a random `RATE_LIMIT_SALT`.
5. Confirm Auth public signup is disabled. Invite each organizer through the Supabase dashboard.
6. Verify the three storage buckets. `private-media` and `submission-quarantine` must remain private.
7. Run `supabase db test` and exercise the role matrix before production.

Never place the service-role key in Vercel public variables, browser code, an iOS plist, or an app binary. It is injected only into hosted Edge Functions.

## Vercel

Import the repository, set the root directory to `apps/admin`, and use pnpm. Configure:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (or the legacy `NEXT_PUBLIC_SUPABASE_ANON_KEY`)
- `NEXT_PUBLIC_SITE_URL`

Set the same production portal URL in Supabase Auth redirect URLs and `ALLOWED_ORIGIN`. Deploy a preview against staging before promoting.

## iOS and TestFlight

1. Open `apps/ios/BirthdayGO/project.yml`; replace `com.example.BirthdayGO` with the registered bundle ID.
2. Run `xcodegen generate`, select the Apple development team, and set `BG_API_BASE_URL` for Release to the hosted functions URL ending in `/functions/v1/`.
3. Add associated domains only after a real HTTPS domain serves a valid `apple-app-site-association` file.
4. Replace or approve the generated original app icon, provide final organizer-approved creature artwork, and verify all usage descriptions.
5. In Xcode, run tests on a real supported iPhone, then Product → Archive → Validate App.
6. Upload through Xcode Organizer, complete App Store Connect privacy answers, encryption/export compliance, age rating, and TestFlight review details.
7. Invite internal testers first. Do not distribute real invitation links in public tester notes.

Apple credentials, signing certificates, App Store Connect records, domain verification, hosted secrets, and successful review require the owner's action. This repository does not claim those external steps are complete.

## Release rollback

- Portal: promote the previous known-good Vercel deployment.
- Edge Functions: redeploy the previous tagged source.
- Database: migrations are forward-only. Test a corrective migration in staging; never restore production over live progress without a reviewed incident plan.
- Game content: unpublish the game or archive affected content. Do not delete published progress sources.
