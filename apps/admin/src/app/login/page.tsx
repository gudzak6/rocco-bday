import { login } from "./actions";

export default async function Login({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <section className="mx-auto max-w-md py-16">
      <form action={login} className="card space-y-5 p-7">
        <div>
          <p className="font-bold text-[var(--purple)]">Private organizer access</p>
          <h1 className="text-3xl font-black">Welcome back</h1>
        </div>
        {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-red-800">{error}</p>}
        <label className="block font-bold">Email
          <input className="field mt-2" type="email" name="email" autoComplete="email" required />
        </label>
        <label className="block font-bold">Password
          <input className="field mt-2" type="password" name="password" autoComplete="current-password" required minLength={8} />
        </label>
        <button className="button w-full" type="submit">Sign in</button>
        <p className="text-sm text-slate-600">Organizer accounts are invitation-only. There is no player signup here.</p>
      </form>
    </section>
  );
}
