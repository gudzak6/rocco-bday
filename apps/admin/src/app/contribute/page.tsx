import { ContributionForm } from "@/components/contribution-form";
import { publicSupabaseKey, publicSupabaseUrl } from "@/lib/supabase/env";

export default async function Contribute({ searchParams }: { searchParams: Promise<{ token?: string }> }) {
  const { token = "" } = await searchParams;
  const base = publicSupabaseUrl();
  return (
    <section className="mx-auto max-w-2xl py-10">
      <ContributionForm
        initialToken={token}
        endpoint={`${base}/functions/v1/contributor-submit`}
        apiKey={publicSupabaseKey()}
      />
      <p className="mt-5 text-center text-sm text-slate-600">Submissions are private, moderated, and never published automatically. Ask the organizer to revoke or delete your contribution.</p>
    </section>
  );
}
