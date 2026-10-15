import { describe, expect, it } from "vitest";
import { GameInput, ProximityInput, SubmissionInput } from "./index";

describe("shared contracts", () => {
  it("rejects submission without explicit consent", () => {
    expect(SubmissionInput.safeParse({
      invitationToken: "x".repeat(32),
      displayName: "Friend",
      message: "Happy birthday!",
      consent: false,
    }).success).toBe(false);
  });

  it("rejects impossible coordinates and poor typed payloads", () => {
    expect(ProximityInput.safeParse({
      contentType: "character",
      contentId: crypto.randomUUID(),
      latitude: 91,
      longitude: 0,
      horizontalAccuracy: 10,
      dwellStartedAt: new Date().toISOString(),
      idempotencyKey: crypto.randomUUID(),
    }).success).toBe(false);
  });

  it("normalizes a valid game draft", () => {
    const result = GameInput.parse({ title: "Adventure", recipientName: "Alex" });
    expect(result.introMessage).toBe("");
    expect(result.launchAt).toBeNull();
  });

  it("accepts a location unlock payload with an idempotency key", () => {
    const result = ProximityInput.safeParse({
      contentType: "character",
      contentId: crypto.randomUUID(),
      latitude: 40.7128,
      longitude: -74.006,
      horizontalAccuracy: 12,
      dwellStartedAt: new Date().toISOString(),
      idempotencyKey: crypto.randomUUID(),
      fallbackCode: "closed-venue",
    });
    expect(result.success).toBe(true);
  });
});
