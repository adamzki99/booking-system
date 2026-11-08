import { test, expect } from "@playwright/test";

test("login with email code", async ({ page }) => {
  const email = process.env.TEST_USER_EMAIL as string;
  const code = process.env.LOGIN_CODE as string;

  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Request code" }).click();
  await expect(page.getByText("A login code was sent")).toBeVisible();
  await page.getByLabel("Code").fill(code);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole("heading", { name: "Booking calendar" })).toBeVisible();
});
