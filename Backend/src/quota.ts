// Hạn mức theo tháng của một người đăng ký. Phần tính là hàm thuần để test; Durable Object chỉ lưu và gọi chúng.

export interface QuotaState {
  /** "2026-10": tháng đang đếm. Sang tháng khác thì `used` về 0. */
  month: string;
  used: number;
  /** Lượt nạp thêm còn lại; không hết hạn theo tháng. */
  credits: number;
  /** Mã giao dịch nạp thêm đã cộng, để một giao dịch không được cộng hai lần. */
  topUps: string[];
}

export interface QuotaView {
  used: number;
  limit: number;
  credits: number;
  remaining: number;
  /** Đầu tháng sau (UTC), ISO 8601. */
  resetsAt: string;
}

export const emptyQuota = (month: string): QuotaState => ({ month, used: 0, credits: 0, topUps: [] });

export function monthKey(now: Date): string {
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
}

/** Trạng thái của tháng hiện tại: sang tháng mới thì bộ đếm về 0, lượt nạp thêm giữ nguyên. */
export function rollOver(state: QuotaState | undefined, now: Date): QuotaState {
  const month = monthKey(now);
  if (!state) return emptyQuota(month);
  return state.month === month ? state : { ...state, month, used: 0 };
}

export function view(state: QuotaState, limit: number, now: Date): QuotaView {
  const reset = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  return {
    used: state.used,
    limit,
    credits: state.credits,
    remaining: Math.max(0, limit - state.used) + state.credits,
    resetsAt: reset.toISOString(),
  };
}

/** Trừ một lượt: dùng lượt của tháng trước, hết thì dùng lượt nạp thêm. Null khi không còn lượt nào. */
export function consume(state: QuotaState, limit: number): QuotaState | null {
  if (state.used < limit) return { ...state, used: state.used + 1 };
  if (state.credits > 0) return { ...state, credits: state.credits - 1 };
  return null;
}

/** Trả lại lượt vừa trừ khi lời gọi mô hình thất bại. */
export function refund(state: QuotaState, usedCredit: boolean): QuotaState {
  return usedCredit ? { ...state, credits: state.credits + 1 } : { ...state, used: Math.max(0, state.used - 1) };
}

/** Cộng lượt nạp thêm; cùng một giao dịch chỉ cộng một lần. */
export function topUp(state: QuotaState, transactionId: string, credits: number): { state: QuotaState; added: boolean } {
  if (state.topUps.includes(transactionId)) return { state, added: false };
  return { state: { ...state, credits: state.credits + credits, topUps: [...state.topUps, transactionId].slice(-200) }, added: true };
}

interface Env {
  MONTHLY_LIMIT: string;
  TOPUP_CREDITS: string;
}

/** Một Durable Object cho mỗi `originalTransactionId`. Mọi thao tác đi qua đây nên không có hai lượt trừ chen nhau. */
export class QuotaObject {
  private readonly storage: DurableObjectStorage;
  private readonly env: Env;

  constructor(state: DurableObjectState, env: Env) {
    this.storage = state.storage;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const now = new Date();
    const limit = Number(this.env.MONTHLY_LIMIT) || 0;
    let state = rollOver(await this.storage.get<QuotaState>("quota"), now);
    let ok = true;
    let usedCredit = false;

    switch (url.pathname) {
      case "/consume": {
        usedCredit = state.used >= limit;
        const next = consume(state, limit);
        if (next) state = next;
        else ok = false;
        break;
      }
      case "/refund":
        state = refund(state, url.searchParams.get("credit") === "1");
        break;
      case "/topup": {
        const result = topUp(state, url.searchParams.get("id") ?? "", Number(this.env.TOPUP_CREDITS) || 0);
        state = result.state;
        ok = result.added;
        break;
      }
      case "/view":
        break;
      default:
        return new Response("not found", { status: 404 });
    }
    await this.storage.put("quota", state);
    return Response.json({ ok, usedCredit, quota: view(state, limit, now) });
  }
}
