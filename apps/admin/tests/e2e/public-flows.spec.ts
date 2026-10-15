import { expect, test } from "@playwright/test";

test("organizer landing page exposes private entry points", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: /Turn favorite places/ })).toBeVisible();
  await expect(page.getByRole("link", { name: "Organizer sign in" })).toBeVisible();
  await expect(page.getByText("No ads, consumables, leaderboards, or public profiles.")).toBeVisible();
});

test("privacy page is linked for contributors and organizers", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("link", { name: "Privacy" }).click();
  await expect(page.getByRole("heading", { name: /How Birthday GO handles personal data/ })).toBeVisible();
});

test("contribution form validates consent and required content", async ({ page }) => {
  await page.goto("/contribute?token=" + "a".repeat(64));
  await expect(page.getByRole("heading", { name: "Add to the birthday adventure" })).toBeVisible();
  await page.getByLabel("Your display name").fill("Taylor");
  await page.getByLabel("Birthday message").fill("Happy birthday!");
  await page.getByRole("button", { name: "Send for organizer review" }).click();
  await expect(page.getByText(/I consent/)).toBeVisible();
});
