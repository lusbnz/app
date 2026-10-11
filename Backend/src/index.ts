// Pennyline AI: proxy nhỏ đứng giữa app và Claude. Giữ khóa API, kiểm tra gói đăng ký với Apple, đếm lượt dùng theo tháng.
// Không lưu nội dung người dùng gửi: chỉ lưu bộ đếm lượt theo mã đăng ký.

import { fetchPurchase, fetchSubscription, isTransactionId, type AppleEnv } from "./apple.ts";
import { anthropicBody, textOf, validate, type TaskRequest } from "./prompts.ts";
import type { QuotaView } from "./quota.ts";

export { QuotaObject } from "./quota.ts";

interface Env extends AppleEnv {
  ANTHROPIC_API_KEY: string;
  AI_PRODUCT_ID: string;
  TOPUP_PRODUCT_ID: string;
  MONTHLY_LIMIT: string;
  TOPUP_CREDITS: string;
  QUOTA: DurableObjectNamespace;
}

interface QuotaReply {
  ok: boolean;
  usedCredit: boolean;
  quota: QuotaView;
}

const json = (body: unknown, status = 200): Response => Response.json(body, { status });

async function quota(env: Env, subscriber: string, path: string): Promise<QuotaReply> {
  const stub = env.QUOTA.get(env.QUOTA.idFromName(subscriber));
  return (await (await stub.fetch(`https://quota${path}`)).json()) as QuotaReply;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const now = new Date();
    if (url.pathname === "/") return json({ service: "pennyline-ai" });

    // Mọi đường khác đều cần một gói AI còn hiệu lực.
    const transactionId = request.headers.get("X-Pennyline-Transaction") ?? "";
    if (!isTransactionId(transactionId)) return json({ error: "unauthorized" }, 401);
    const subscription = await fetchSubscription(env, transactionId, env.AI_PRODUCT_ID, now);
    if (!subscription) return json({ error: "not_subscribed" }, 403);
    const subscriber = subscription.originalTransactionId;

    if (request.method === "GET" && url.pathname === "/v1/quota") {
      return json({ quota: (await quota(env, subscriber, "/view")).quota });
    }

    if (request.method === "POST" && url.pathname === "/v1/topup") {
      const body = (await request.json().catch(() => ({}))) as { transactionId?: string };
      const id = body.transactionId ?? "";
      if (!isTransactionId(id) || !(await fetchPurchase(env, id, env.TOPUP_PRODUCT_ID, now))) return json({ error: "invalid_purchase" }, 400);
      const reply = await quota(env, subscriber, `/topup?id=${id}`);
      return json({ added: reply.ok, quota: reply.quota });
    }

    if (request.method === "POST" && url.pathname === "/v1/run") {
      const body = (await request.json().catch(() => ({}))) as Partial<TaskRequest>;
      const problem = validate(body);
      if (problem) return json({ error: "bad_request", field: problem }, 400);

      const spent = await quota(env, subscriber, "/consume");
      if (!spent.ok) return json({ error: "quota_exceeded", quota: spent.quota }, 429);

      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "content-type": "application/json", "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01" },
        body: JSON.stringify(anthropicBody(body as TaskRequest)),
      });
      if (!response.ok) {
        // Mô hình lỗi thì trả lại lượt vừa trừ.
        const refunded = await quota(env, subscriber, `/refund?credit=${spent.usedCredit ? 1 : 0}`);
        return json({ error: "model_unavailable", quota: refunded.quota }, 502);
      }
      return json({ text: textOf(await response.json()), quota: spent.quota });
    }

    return json({ error: "not_found" }, 404);
  },
};
