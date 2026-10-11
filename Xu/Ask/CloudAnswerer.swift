import Foundation

/// Trả lời Hỏi Pennyline bằng gói AI (Claude qua Worker), cho máy không có mô hình trên máy. Cùng luật với bản trên máy:
/// mô hình chỉ thấy bảng số liệu đã tính sẵn, và câu trả lời có con số lạ thì bị loại.
struct CloudAnswerer: SpendingAnswering {
    let calendar: Calendar
    let run: @Sendable (AIRunRequest) async throws -> String

    func answer(_ question: String, context: SpendingSnapshot) async throws -> String {
        let sheet = SpendingFacts.sheet(context, calendar: calendar) { key in
            context.categoryNames[key] ?? String(localized: SpendingCategory(key: key).title)
        }
        let answer = try await run(AIRunRequest(task: .ask, sheet: sheet, text: question, language: AILanguage.current))
        guard !answer.isEmpty else { throw AskError.emptyAnswer }
        guard SpendingFacts.usesOnlyKnownNumbers(answer, sheet: sheet, question: question) else { throw AskError.unverifiedNumbers }
        return answer
    }
}

enum AILanguage {
    /// Ngôn ngữ giao diện đang dùng, để AI trả lời cùng ngôn ngữ.
    static var current: String {
        (Bundle.main.preferredLocalizations.first ?? "vi").hasPrefix("vi") ? "vi" : "en"
    }
}
