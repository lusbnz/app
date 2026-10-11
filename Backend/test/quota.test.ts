import assert from "node:assert/strict";
import { test } from "node:test";
import { consume, emptyQuota, monthKey, refund, rollOver, topUp, view } from "../src/quota.ts";

const october = new Date(Date.UTC(2026, 9, 10, 8));

test("month key is padded UTC", () => {
  assert.equal(monthKey(october), "2026-10");
  assert.equal(monthKey(new Date(Date.UTC(2027, 0, 1))), "2027-01");
});

test("a new month resets usage but keeps credits", () => {
  const state = { month: "2026-09", used: 300, credits: 40, topUps: ["1"] };
  assert.deepEqual(rollOver(state, october), { month: "2026-10", used: 0, credits: 40, topUps: ["1"] });
  assert.deepEqual(rollOver(undefined, october), emptyQuota("2026-10"));
  assert.equal(rollOver({ ...state, month: "2026-10" }, october).used, 300);
});

test("plan uses are spent before credits, then nothing is left", () => {
  let state = { month: "2026-10", used: 1, credits: 1, topUps: [] as string[] };
  state = consume(state, 2)!;
  assert.deepEqual([state.used, state.credits], [2, 1]);
  state = consume(state, 2)!;
  assert.deepEqual([state.used, state.credits], [2, 0]);
  assert.equal(consume(state, 2), null);
});

test("a refund gives back what was spent", () => {
  assert.equal(refund({ month: "m", used: 3, credits: 0, topUps: [] }, false).used, 2);
  assert.equal(refund({ month: "m", used: 3, credits: 0, topUps: [] }, true).credits, 1);
  assert.equal(refund({ month: "m", used: 0, credits: 0, topUps: [] }, false).used, 0);
});

test("a top-up counts once per transaction", () => {
  const first = topUp(emptyQuota("2026-10"), "777", 100);
  assert.equal(first.added, true);
  assert.equal(first.state.credits, 100);
  const again = topUp(first.state, "777", 100);
  assert.equal(again.added, false);
  assert.equal(again.state.credits, 100);
});

test("the view reports what is left and when it resets", () => {
  const shown = view({ month: "2026-10", used: 250, credits: 20, topUps: [] }, 300, october);
  assert.deepEqual(shown, { used: 250, limit: 300, credits: 20, remaining: 70, resetsAt: "2026-11-01T00:00:00.000Z" });
  assert.equal(view({ month: "2026-10", used: 400, credits: 0, topUps: [] }, 300, october).remaining, 0);
});
