import Foundation

/// Chạy một câu hỏi qua mô hình trả lời. Ô gõ và màn Tháng dùng chung để cùng một lời nhắn khi mô hình không trả lời chắc được.
@MainActor
enum AskRunner {
    static var fallbackAnswer: String {
        String(localized: "Pennyline chưa trả lời chắc được câu này. Bạn thử hỏi cách khác nhé.")
    }

    /// Câu trả lời, hoặc lời nhắn thay thế khi mô hình lỗi hay đưa ra con số lạ. Nil khi máy không có mô hình để hỏi.
    static func answer(
        _ question: String, snapshot: SpendingSnapshot, calendar: Calendar, answerer: (any SpendingAnswering)? = nil
    ) async -> String? {
        guard let answerer = answerer ?? AskEngine.makeAnswerer(calendar: calendar) else { return nil }
        do {
            return try await answerer.answer(question, context: snapshot)
        } catch {
            return fallbackAnswer
        }
    }
}
