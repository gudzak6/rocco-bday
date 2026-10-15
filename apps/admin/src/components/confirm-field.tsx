"use client";

import { useState } from "react";

export function ConfirmField({
  expected,
  label,
  children,
}: {
  expected: string;
  label: string;
  children: React.ReactNode;
}) {
  const [value, setValue] = useState("");
  return (
    <div className="flex flex-wrap items-end gap-2">
      <label className="text-sm">
        {label}
        <input
          className="field mt-1"
          name="confirmation"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          autoComplete="off"
        />
      </label>
      <span className={value === expected ? "" : "pointer-events-none opacity-40"}>{children}</span>
    </div>
  );
}
