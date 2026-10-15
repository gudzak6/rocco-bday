import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { logout } from "../login/actions";
import { createGame } from "./actions";

export default async function Dashboard() {
  const supabase = await createClient();
  const { data: games } = await supabase.from("games")
    .select("id,title,recipient_name,state,updated_at").order("updated_at", { ascending: false });

  return (
    <div className="space-y-8 py-8">
      <div className="flex items-end justify-between gap-4">
        <div><p className="font-bold text-[var(--purple)]">Organizer</p><h1 className="text-4xl font-black">Your adventures</h1></div>
        <form action={logout}><button className="button secondary">Sign out</button></form>
      </div>
      <div className="grid gap-6 lg:grid-cols-[1fr_22rem]">
        <section className="space-y-3" aria-label="Games">
          {games?.map((game) => (
            <Link className="card flex items-center justify-between p-5 transition hover:-translate-y-0.5" href={`/dashboard/games/${game.id}`} key={game.id}>
              <span><strong className="block text-xl">{game.title}</strong><span className="text-slate-600">For {game.recipient_name}</span></span>
              <span className="rounded-full bg-slate-100 px-3 py-1 text-sm font-bold capitalize">{game.state}</span>
            </Link>
          ))}
          {!games?.length && <div className="card p-8 text-center text-slate-600">Create the first birthday adventure.</div>}
        </section>
        <form action={createGame} className="card space-y-4 p-5">
          <h2 className="text-xl font-black">New adventure</h2>
          <label className="block font-bold">Game title<input className="field mt-1" name="title" required maxLength={100} /></label>
          <label className="block font-bold">Recipient name<input className="field mt-1" name="recipientName" required maxLength={80} /></label>
          <label className="block font-bold">Welcome message<textarea className="field mt-1" name="introMessage" rows={4} maxLength={2000} placeholder="Optional — a starter adventure is added automatically." /></label>
          <p className="text-sm text-slate-600">This creates a published starter with example places, creatures, notes, and a finale. You can edit or replace all of it.</p>
          <button className="button w-full">Create with examples</button>
        </form>
      </div>
    </div>
  );
}
