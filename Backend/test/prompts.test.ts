import assert from "node:assert/strict";
import { test } from "node:test";
import { anthropicBody, limits, textOf, userMessage, validate } from "../src/prompts.ts";

test("requests are validated per task", () => {
  assert.equal(validate({ task: "ask", text: "cf hết bao nhiêu?", sheet: "Đã tiêu: 1tr" }), null);
  assert.equal(validate({ task: "insight", sheet: "Đã tiêu: 1tr" }), null);
  assert.equal(validate({ task: "normalize", text: "ăn hết bốn trăm rưỡi" }), null);
  assert.equal(validate({}), "task");
  assert.equal(validate({ task: "ask", text: "  ", sheet: "x" }), "text");
  assert.equal(validate({ task: "ask", text: "x" }), "sheet");
  assert.equal(validate({ task: "normalize", text: "x".repeat(limits.text + 1) }), "too_long");
  assert.equal(validate({ task: "insight", sheet: "x".repeat(limits.sheet + 1) }), "too_long");
});

test("the request to the model uses the task's model and caches the fixed instructions", () => {
  const body = anthropicBody({ task: "normalize", text: "ăn hết bốn trăm rưỡi" }) as { model: string; max_tokens: number; system: { cache_control: unknown }[]; messages: { content: string }[] };
  assert.equal(body.model, "claude-haiku-5-5");
  assert.deepEqual(body.system[0]!.cache_control, { type: "ephemeral" });
  assert.equal(body.messages[0]!.content, "Câu gốc: ăn hết bốn trăm rưỡi");
  assert.equal((anthropicBody({ task: "ask", text: "q", sheet: "s" }) as { model: string }).model, "claude-sonnet-5-5");
});

test("the user message carries the sheet, the question and the answer language", () => {
  const message = userMessage({ task: "ask", text: "cf?", sheet: "- cf: 232k", language: "en" });
  assert.ok(message.includes("- cf: 232k") && message.includes("Câu hỏi: cf?") && message.includes("tiếng Anh"));
  assert.ok(userMessage({ task: "insight", sheet: "s" }).includes("tiếng Việt"));
});

test("only text blocks of the reply are kept", () => {
  assert.equal(textOf({ content: [{ type: "text", text: " 232k " }, { type: "tool_use" }, { type: "text", text: "cho 8 lần." }] }), "232k cho 8 lần.");
  assert.equal(textOf({}), "");
});
