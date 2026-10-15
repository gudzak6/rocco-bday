# Privacy and safety

Birthday GO is designed for one recipient and a small invited group.

- The app requests foreground location only. It does not request background location or retain a GPS trail.
- The camera is used only during a catch so a birthday creature can appear in AR. Frames are not recorded, stored, or uploaded.
- Unlock requests use a current coordinate, accuracy, and dwell timestamp transiently. Audit records contain the attempted content ID, not coordinates.
- Locked message bodies and private media are omitted from player responses until a server-confirmed unlock.
- Player access tokens are opaque, hashed at rest, bound to an installation, and stored in iOS Keychain.
- Organizer authentication is handled by Supabase Auth. Contributor links expire, can be revoked, and grant submission permission only.
- Friend uploads remain in a private quarantine bucket pending moderation. Published sensitive media remains private and uses expiring signed URLs.
- Continuous location analytics, advertising IDs, trackers, multiplayer profiles, and leaderboards are not used.

Before launch, publish a product-specific privacy policy naming the operator, contact address, retention periods, subprocessors (Supabase and Vercel), legal basis, and jurisdiction. Configure an organizer process for contribution export/deletion requests. Revoke lost devices in `player_devices` and issue recovery access through a reviewed organizer flow.

Do not include home addresses in hints or screenshots. Prefer public, safe, accessible places and provide a fallback unlock code for every venue-dependent required item.
