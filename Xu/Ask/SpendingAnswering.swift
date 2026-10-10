import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

protocol SpendingAnswering: Sendable {
    func answer(_ question: String, context: SpendingSnapshot) async throws -> String
}

enum AskError: Error {
    /// Mô hình đưa ra con số không có trong số liệu, nên câu trả lời bị bỏ.
    case unverifiedNumbers
    case emptyAnswer
}

/// Chọn cách trả lời. Bản này chỉ có mô hình trên máy của Apple; không gọi dịch vụ ngoài.
enum AskEngine {
    private static let vietnamese = Locale(identifier: "vi_VN")

    /// Mô hình trên máy có sẵn và hỗ trợ tiếng Việt.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            return model.isAvailable && model.supportsLocale(vietnamese)
        }
        #endif
        return false
    }

    static func makeAnswerer(calendar: Calendar) -> (any SpendingAnswering)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            return OnDeviceAnswerer(calendar: calendar)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
/// Trả lời bằng Foundation Models. Mô hình chỉ chọn số liệu và diễn đạt;
/// câu trả lời có con số lạ sẽ bị loại.
@available(iOS 26.0, *)
struct OnDeviceAnswerer: SpendingAnswering {
    let calendar: Calendar

    private static let instructions = """
        Bạn là Nhẩm, trợ lý ghi chi tiêu. Trả lời bằng tiếng Việt, một hoặc hai câu ngắn, không chào hỏi.
        Chỉ dùng các con số có trong bảng số liệu và chép nguyên văn, ví dụ "232k", "8 lần", "7,1tr".
        Không cộng, trừ, nhân, chia, không ước lượng, không tự nghĩ ra con số.
        Nếu bảng số liệu không đủ để trả lời, hãy nói: "Nhẩm chưa có số liệu cho câu này."
        Ví dụ: hỏi "tháng này cf hết bao nhiêu?" thì trả lời "232k cho 8 lần, trung bình 29k mỗi lần."
        """

    func answer(_ question: String, context: SpendingSnapshot) async throws -> String {
        let sheet = SpendingFacts.sheet(context, calendar: calendar) { key in
            context.categoryNames[key] ?? String(localized: SpendingCategory(key: key).title)
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Bảng số liệu tháng này:\n\(sheet)\n\nCâu hỏi: \(question)",
            options: GenerationOptions(temperature: 0)
        )
        let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AskError.emptyAnswer }
        guard SpendingFacts.usesOnlyKnownNumbers(answer, sheet: sheet, question: question) else {
            throw AskError.unverifiedNumbers
        }
        return answer
    }
}
#endif
