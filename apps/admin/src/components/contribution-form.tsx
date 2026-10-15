"use client";

import { FormEvent, useState } from "react";

export function ContributionForm({
  initialToken, endpoint, apiKey,
}: { initialToken: string; endpoint: string; apiKey?: string }) {
  const [status, setStatus] = useState<"idle" | "sending" | "sent">("idle");
  const [error, setError] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(""); setStatus("sending");
    const form = new FormData(event.currentTarget);
    form.set("consent", "true");
    const audio = form.get("audio");
    if (audio instanceof File && audio.size) {
      try {
        const duration = await mediaDuration(audio);
        if (duration > 600) throw new Error("Audio must be 10 minutes or less.");
        form.set("durationSeconds", String(Math.round(duration)));
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : "Audio could not be read.");
        setStatus("idle"); return;
      }
    }
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        body: form,
        headers: apiKey ? { apikey: apiKey } : undefined,
      });
      const result = await response.json() as { error?: string };
      if (!response.ok) throw new Error(result.error?.replaceAll("_", " ") ?? "Submission failed");
      setStatus("sent");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Submission failed");
      setStatus("idle");
    }
  }

  if (status === "sent") {
    return <div className="card p-8 text-center" role="status"><div className="text-5xl">💌</div><h1 className="mt-4 text-3xl font-black">Your surprise is on its way!</h1><p className="mt-2 text-slate-600">The organizer will review it before the recipient can see it.</p></div>;
  }

  return (
    <form className="card space-y-5 p-6" onSubmit={submit}>
      <div><p className="font-bold text-[var(--purple)]">Birthday note</p><h1 className="text-3xl font-black">Leave a birthday message</h1><p className="mt-2 text-slate-600">No app install or account needed. The organizer reviews every note before it appears in Memories.</p></div>
      {error && <p role="alert" className="rounded-lg bg-red-50 p-3 capitalize text-red-800">{error}</p>}
      <label className="block font-bold">Invitation secret<input className="field mt-1" name="invitationToken" defaultValue={initialToken} required minLength={32} /></label>
      <label className="block font-bold">Your name<input className="field mt-1" name="displayName" required maxLength={80} /></label>
      <label className="block font-bold">Birthday message<textarea className="field mt-1" name="message" required maxLength={5000} rows={7} /></label>
      <label className="block font-bold">Photo <span className="font-normal text-slate-500">(optional, JPG/PNG/WebP, 10 MB)</span><input className="field mt-1" name="photo" type="file" accept="image/jpeg,image/png,image/webp" /></label>
      <label className="block font-bold">Voice recording <span className="font-normal text-slate-500">(optional, 10 minutes/15 MB)</span><input className="field mt-1" name="audio" type="file" accept="audio/mpeg,audio/mp4,audio/x-m4a" /></label>
      <label className="block font-bold">Suggested location or shared memory<textarea className="field mt-1" name="memorySuggestion" maxLength={2000} /></label>
      <label className="block font-bold">Place name<input className="field mt-1" name="locationSuggestion" maxLength={500} /></label>
      <label className="block font-bold">Optional character association<textarea className="field mt-1" name="characterIdea" maxLength={1000} placeholder="Chair Cat, Confused Anya, a roommate…" /></label>
      <input className="hidden" name="website" tabIndex={-1} autoComplete="off" aria-hidden />
      <label className="flex items-start gap-3 text-sm"><input className="mt-1" type="checkbox" required />I consent to share this content with the birthday recipient and organizer. I have permission to share uploaded media.</label>
      <button className="button w-full" disabled={status === "sending"}>{status === "sending" ? "Sending securely…" : "Send for organizer review"}</button>
    </form>
  );
}

function mediaDuration(file: File) {
  return new Promise<number>((resolve, reject) => {
    const audio = document.createElement("audio");
    const url = URL.createObjectURL(file);
    audio.preload = "metadata";
    audio.onloadedmetadata = () => { URL.revokeObjectURL(url); resolve(audio.duration); };
    audio.onerror = () => { URL.revokeObjectURL(url); reject(new Error("Audio could not be read.")); };
    audio.src = url;
  });
}
