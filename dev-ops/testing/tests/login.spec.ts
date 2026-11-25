import { test, expect } from "@playwright/test";

test("login in QA mode", async ({ page }) => {
  const email = process.env.TEST_USER_EMAIL as string;

  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole("heading", { name: "Booking calendar" })).toBeVisible();
});
