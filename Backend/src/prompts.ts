// Ba việc gói AI làm. App chỉ gửi bảng số liệu đã gộp sẵn hoặc một dòng chữ người dùng vừa gõ, không gửi dữ liệu thô.

export type Task = "ask" | "insight" | "normalize";

export interface TaskRequest {
  task: Task;
  /** Bảng số liệu tháng đã tính sẵn (ask, insight). */
  sheet?: string;
  /** Câu hỏi (ask) hoặc dòng chữ cần viết lại (normalize). */
  text?: string;
  /** "vi" hoặc "en": ngôn ngữ trả lời. */
  language?: string;
}

export const limits = { sheet: 12_000, text: 500 };

/** Việc rẻ và nhiều dùng Haiku; hỏi đáp và nhận xét dùng Sonnet. */
export const models: Record<Task, string> = {
  normalize: "claude-haiku-5-5",
  ask: "claude-sonnet-5-5",
  insight: "claude-sonnet-5-5",
};

export const maxTokens: Record<Task, number> = { normalize: 120, ask: 300, insight: 400 };

const numbersRule =
  'Chỉ dùng các con số có trong bảng số liệu và chép nguyên văn, ví dụ "232k", "8 lần", "7,1tr". Không cộng, trừ, nhân, chia, không ước lượng, không tự nghĩ ra con số.';

export const systemPrompts: Record<Task, string> = {
  ask: `Bạn là Pennyline, trợ lý ghi chi tiêu. Trả lời một hoặc hai câu ngắn, không chào hỏi. ${numbersRule} Nếu bảng số liệu không đủ để trả lời, hãy nói: "Pennyline chưa có số liệu cho câu này."`,
  insight: `Bạn là Pennyline, trợ lý ghi chi tiêu. Viết nhận xét về tháng này trong ba đến bốn câu ngắn: điểm đáng chú ý nhất, một điều đang tốt, và một gợi ý cụ thể làm được ngay. Giọng thân thiện, không phán xét, không chào hỏi, không gạch đầu dòng. ${numbersRule}`,
  normalize: `Bạn viết lại một câu nói về khoản chi thành đúng một dòng ngắn để một bộ tách cứng đọc được. Dạng dòng: "<tên khoản> <số tiền>[ chia <số người>][ <ngày>]". Số tiền viết bằng chữ số kèm k hoặc tr ("450k", "1tr2"). Ngày chỉ dùng: "hôm qua", "hôm kia", "tối qua", "sáng nay", "<N> ngày trước", "thứ <2-7>", "chủ nhật", "ngày <D>/<M>". Nhiều khoản thì ngăn bằng dấu phẩy. Không thêm khoản hay con số không có trong câu gốc. Chỉ trả về dòng đó, không giải thích. Nếu câu không nói về khoản chi nào, trả về chuỗi rỗng.`,
};

/** Lỗi của yêu cầu, hoặc null khi hợp lệ. */
export function validate(request: Partial<TaskRequest>): string | null {
  if (request.task !== "ask" && request.task !== "insight" && request.task !== "normalize") return "task";
  const text = request.text ?? "";
  const sheet = request.sheet ?? "";
  if (text.length > limits.text || sheet.length > limits.sheet) return "too_long";
  if (request.task !== "insight" && text.trim() === "") return "text";
  if (request.task !== "normalize" && sheet.trim() === "") return "sheet";
  return null;
}

export function userMessage(request: TaskRequest): string {
  const language = request.language === "en" ? "Trả lời bằng tiếng Anh." : "Trả lời bằng tiếng Việt.";
  switch (request.task) {
    case "ask":
      return `Bảng số liệu tháng này:\n${request.sheet}\n\nCâu hỏi: ${request.text}\n\n${language}`;
    case "insight":
      return `Bảng số liệu tháng này:\n${request.sheet}\n\n${language}`;
    case "normalize":
      return `Câu gốc: ${request.text}`;
  }
}

/** Thân yêu cầu gửi Anthropic Messages API. Lời hướng dẫn cố định được đánh dấu để lưu đệm. */
export function anthropicBody(request: TaskRequest): unknown {
  return {
    model: models[request.task],
    max_tokens: maxTokens[request.task],
    system: [{ type: "text", text: systemPrompts[request.task], cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content: userMessage(request) }],
  };
}

/** Chữ trong câu trả lời của Messages API. */
export function textOf(response: unknown): string {
  const content = (response as { content?: { type: string; text?: string }[] }).content ?? [];
  return content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();
}
