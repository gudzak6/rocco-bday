"use client";

export default function DashboardError({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <div className="card mt-10 space-y-4 p-6">
      <h1 className="text-2xl font-black">That change could not be saved</h1>
      <p role="alert">{error.message}</p>
      <button className="button" onClick={reset}>Try again</button>
    </div>
  );
}
