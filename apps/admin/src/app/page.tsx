import Link from "next/link";

export default function Home() {
  return (
    <section className="grid min-h-[70vh] items-center gap-10 py-12 md:grid-cols-2">
      <div>
        <p className="mb-3 font-bold text-[var(--purple)]">A one-of-one birthday adventure</p>
        <h1 className="text-5xl font-black leading-tight">Turn favorite places into heartfelt surprises.</h1>
        <p className="mt-5 max-w-xl text-lg text-slate-600">
          Build a private map of original characters, friend notes, memories, and one unforgettable finale.
        </p>
        <div className="mt-8 flex gap-3">
          <Link className="button" href="/login">Organizer sign in</Link>
          <Link className="button secondary" href="/contribute">Contribute with an invite</Link>
        </div>
      </div>
      <div className="card relative overflow-hidden p-10 text-center">
        <div aria-hidden className="mx-auto grid size-48 place-items-center rounded-full bg-gradient-to-b from-[var(--sky)] to-[var(--purple)] shadow-2xl">
          <span className="text-7xl">🎁</span>
        </div>
        <h2 className="mt-7 text-2xl font-black">Explore. Catch. Remember.</h2>
        <p className="mt-2 text-slate-600">No ads, consumables, leaderboards, or public profiles.</p>
      </div>
    </section>
  );
}
