// Kiểm tra gói đăng ký với App Store Server API. Worker không tin dữ liệu app gửi lên: nó chỉ lấy mã giao dịch
// rồi hỏi thẳng Apple (qua TLS, ký bằng khóa In-App Purchase của nhà phát triển) xem gói còn hiệu lực không.

export interface AppleEnv {
  APPLE_ISSUER_ID: string;
  APPLE_KEY_ID: string;
  APPLE_PRIVATE_KEY: string;
  APPLE_ENVIRONMENT: string;
  BUNDLE_ID: string;
}

export interface TransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  expiresDate?: number;
  revocationDate?: number;
}

const encoder = new TextEncoder();

export function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? encoder.encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromBase64url(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(text.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

/** Khóa .p8 (PKCS#8, PEM) thành khóa ký ES256. */
export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return crypto.subtle.importKey("pkcs8", fromBase64url(body.replace(/\+/g, "-").replace(/\//g, "_")), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/** JWT cho App Store Server API, sống 5 phút. */
export async function appStoreToken(env: AppleEnv, now: Date, key?: CryptoKey): Promise<string> {
  const issued = Math.floor(now.getTime() / 1000);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env.APPLE_KEY_ID, typ: "JWT" }));
  const payload = base64url(JSON.stringify({ iss: env.APPLE_ISSUER_ID, iat: issued, exp: issued + 300, aud: "appstoreconnect-v1", bid: env.BUNDLE_ID }));
  const signingKey = key ?? (await importPrivateKey(env.APPLE_PRIVATE_KEY));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signingKey, encoder.encode(`${header}.${payload}`));
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

/** Phần nội dung của một JWS (không kiểm chữ ký: chỉ dùng cho JWS nhận trực tiếp từ Apple qua TLS). */
export function decodePayload<T>(jws: string): T | null {
  const parts = jws.split(".");
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(new TextDecoder().decode(fromBase64url(parts[1]!))) as T;
  } catch {
    return null;
  }
}

/** Mã giao dịch chỉ gồm chữ số; chặn mọi thứ khác trước khi ghép vào đường dẫn. */
export function isTransactionId(text: string): boolean {
  return /^[0-9]{1,32}$/.test(text);
}

function host(env: AppleEnv): string {
  return env.APPLE_ENVIRONMENT === "production" ? "https://api.storekit.itunes.apple.com" : "https://api.storekit-sandbox.itunes.apple.com";
}

interface StatusResponse {
  data?: { lastTransactions?: { status: number; signedTransactionInfo: string }[] }[];
}

/** Gói đăng ký còn hiệu lực (đang chạy hoặc đang trong thời gian gia hạn thanh toán) của đúng app và đúng sản phẩm. */
export function activeSubscription(response: StatusResponse, productId: string, bundleId: string, now: Date): TransactionInfo | null {
  for (const group of response.data ?? []) {
    for (const item of group.lastTransactions ?? []) {
      if (item.status !== 1 && item.status !== 4) continue;
      const info = decodePayload<TransactionInfo>(item.signedTransactionInfo);
      if (!info || info.productId !== productId || info.bundleId !== bundleId || info.revocationDate) continue;
      if (item.status === 1 && info.expiresDate !== undefined && info.expiresDate < now.getTime()) continue;
      return info;
    }
  }
  return null;
}

export async function fetchSubscription(env: AppleEnv, transactionId: string, productId: string, now: Date): Promise<TransactionInfo | null> {
  const response = await fetch(`${host(env)}/inApps/v1/subscriptions/${transactionId}`, {
    headers: { Authorization: `Bearer ${await appStoreToken(env, now)}` },
  });
  if (!response.ok) return null;
  return activeSubscription((await response.json()) as StatusResponse, productId, env.BUNDLE_ID, now);
}

/** Một giao dịch mua lẻ (nạp thêm lượt) có thật, đúng app, đúng sản phẩm và chưa bị hoàn tiền. */
export async function fetchPurchase(env: AppleEnv, transactionId: string, productId: string, now: Date): Promise<TransactionInfo | null> {
  const response = await fetch(`${host(env)}/inApps/v1/transactions/${transactionId}`, {
    headers: { Authorization: `Bearer ${await appStoreToken(env, now)}` },
  });
  if (!response.ok) return null;
  const body = (await response.json()) as { signedTransactionInfo?: string };
  const info = body.signedTransactionInfo ? decodePayload<TransactionInfo>(body.signedTransactionInfo) : null;
  if (!info || info.productId !== productId || info.bundleId !== env.BUNDLE_ID || info.revocationDate) return null;
  return info;
}
