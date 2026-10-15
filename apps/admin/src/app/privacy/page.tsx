export default function Privacy() {
  return (
    <article className="card mx-auto max-w-3xl space-y-4 p-8">
      <p className="font-bold text-[var(--purple)]">Privacy</p>
      <h1 className="text-4xl font-black">How Birthday GO handles personal data</h1>
      <p>Birthday GO is a private adventure for one recipient and a small invited group. It is not a social network and does not use advertising identifiers, trackers, or leaderboards.</p>
      <ul className="list-disc space-y-2 pl-5">
        <li>The iOS app requests foreground location only, and only while Explore is open.</li>
        <li>The camera is used only while catching a birthday creature in AR. Nothing is recorded or uploaded.</li>
        <li>Unlock requests send a current coordinate, accuracy, and dwell timestamp to authorize a surprise. Those coordinates are not stored as a GPS trail.</li>
        <li>Friend contributions stay pending until an organizer reviews them. Locked notes stay on the server until the recipient is eligible.</li>
        <li>Organizer accounts are invitation-only. Contributors use expiring links and do not create passwords.</li>
        <li>Ask the organizer to export or delete a contribution. Lost devices can be revoked from the organizer dashboard.</li>
      </ul>
      <p>Before a public launch, replace this summary with an operator-specific policy that names the organizer, contact address, retention period, subprocessors, and jurisdiction. See the repository privacy guide for the engineering commitments.</p>
    </article>
  );
}
