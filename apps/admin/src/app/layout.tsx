import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Birthday GO Organizer",
  description: "Create a private, location-based birthday adventure.",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <header className="mx-auto flex max-w-6xl items-center justify-between px-5 py-5">
          <Link href="/" className="text-xl font-black text-[var(--purple)]">Birthday GO</Link>
          <nav className="flex items-center gap-3">
            <Link href="/privacy" className="text-sm font-bold text-slate-600">Privacy</Link>
            <span className="rounded-full bg-[var(--gold)] px-3 py-1 text-sm font-bold">Organizer Studio</span>
          </nav>
        </header>
        <main className="mx-auto max-w-6xl px-5 pb-16">{children}</main>
      </body>
    </html>
  );
}
