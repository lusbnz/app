import assert from "node:assert/strict";
import { test } from "node:test";
import { activeSubscription, appStoreToken, base64url, decodePayload, fromBase64url, isTransactionId } from "../src/apple.ts";

const env = { APPLE_ISSUER_ID: "issuer", APPLE_KEY_ID: "KEY123", APPLE_PRIVATE_KEY: "", APPLE_ENVIRONMENT: "sandbox", BUNDLE_ID: "com.quocviet.Xu" };
const now = new Date(Date.UTC(2026, 9, 10));
const jws = (payload: unknown) => `h.${base64url(JSON.stringify(payload))}.s`;
const info = (extra: object = {}) => ({ transactionId: "2", originalTransactionId: "1", productId: "xu.ai.monthly", bundleId: "com.quocviet.Xu", expiresDate: now.getTime() + 86_400_000, ...extra });
const status = (code: number, payload: unknown) => ({ data: [{ lastTransactions: [{ status: code, signedTransactionInfo: jws(payload) }] }] });

test("base64url round trips and has no padding", () => {
  const text = base64url("phở bò?>");
  assert.ok(!/[+/=]/.test(text));
  assert.equal(new TextDecoder().decode(fromBase64url(text)), "phở bò?>");
});

test("the App Store token is a verifiable ES256 JWT with the right claims", async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const token = await appStoreToken(env, now, pair.privateKey);
  const [header, payload, signature] = token.split(".");
  assert.deepEqual(JSON.parse(new TextDecoder().decode(fromBase64url(header!))), { alg: "ES256", kid: "KEY123", typ: "JWT" });
  const claims = decodePayload<{ iss: string; aud: string; bid: string; iat: number; exp: number }>(token)!;
  assert.equal(claims.iss, "issuer");
  assert.equal(claims.aud, "appstoreconnect-v1");
  assert.equal(claims.bid, "com.quocviet.Xu");
  assert.equal(claims.exp - claims.iat, 300);
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, fromBase64url(signature!), new TextEncoder().encode(`${header}.${payload}`));
  assert.equal(valid, true);
});

test("only numeric transaction ids are accepted", () => {
  assert.equal(isTransactionId("2000000123456789"), true);
  for (const bad of ["", "12a", "../x", "1 2", "1".repeat(40)]) assert.equal(isTransactionId(bad), false);
});

test("an active or in-grace subscription of the right app and product is accepted", () => {
  assert.equal(activeSubscription(status(1, info()), "xu.ai.monthly", "com.quocviet.Xu", now)?.originalTransactionId, "1");
  assert.equal(activeSubscription(status(4, info({ expiresDate: now.getTime() - 1 })), "xu.ai.monthly", "com.quocviet.Xu", now)?.originalTransactionId, "1");
});

test("expired, revoked, wrong product, wrong app and malformed entries are rejected", () => {
  const check = (code: number, payload: unknown) => activeSubscription(status(code, payload), "xu.ai.monthly", "com.quocviet.Xu", now);
  assert.equal(check(2, info()), null);
  assert.equal(check(1, info({ expiresDate: now.getTime() - 1 })), null);
  assert.equal(check(1, info({ revocationDate: 5 })), null);
  assert.equal(check(1, info({ productId: "xu.pro.yearly" })), null);
  assert.equal(check(1, info({ bundleId: "com.other.app" })), null);
  assert.equal(activeSubscription({ data: [{ lastTransactions: [{ status: 1, signedTransactionInfo: "not-a-jws" }] }] }, "xu.ai.monthly", "com.quocviet.Xu", now), null);
  assert.equal(activeSubscription({}, "xu.ai.monthly", "com.quocviet.Xu", now), null);
});
