import Foundation

/// Ba việc gói AI làm. Tên trùng với `Task` của Worker (`Backend/src/prompts.ts`).
enum AITask: String, Codable, Sendable {
    /// Trả lời một câu hỏi từ bảng số liệu tháng.
    case ask
    /// Viết nhận xét về tháng từ bảng số liệu.
    case insight
    /// Viết lại một câu nói tự nhiên thành dòng mà bộ tách đọc được.
    case normalize
}

/// Thứ app gửi đi: chỉ bảng số liệu đã gộp sẵn hoặc một dòng chữ người dùng vừa gõ, không bao giờ là dữ liệu thô.
struct AIRunRequest: Codable, Equatable, Sendable {
    var task: AITask
    var sheet: String?
    var text: String?
    /// "vi" hoặc "en".
    var language: String?
}

struct AIQuota: Codable, Equatable, Sendable {
    var used: Int
    var limit: Int
    /// Lượt nạp thêm còn lại, không hết hạn theo tháng.
    var credits: Int
    var remaining: Int
    var resetsAt: Date
}

struct AIRunResponse: Equatable, Sendable {
    var text: String
    var quota: AIQuota
}

enum AIError: Error, Equatable, Sendable {
    /// App chưa được đặt địa chỉ Worker.
    case notConfigured
    /// Chưa có gói AI, hoặc gói đã hết hạn.
    case notSubscribed
    /// Hết lượt của tháng và hết lượt nạp thêm.
    case quotaExceeded(AIQuota?)
    /// Mô hình hoặc Worker đang lỗi; lượt đã được trả lại.
    case unavailable
    /// Không có mạng hoặc câu trả lời không đọc được.
    case network
}

/// Đọc câu trả lời của Worker. Tách riêng khỏi `AIClient` để test không cần mạng.
enum AIProtocol {
    static let transactionHeader = "X-Pennyline-Transaction"

    /// Giới hạn trùng với Worker, để cắt bớt trước khi gửi thay vì bị từ chối.
    static let maxSheetLength = 12_000
    static let maxTextLength = 500

    private struct RunBody: Decodable {
        var text: String?
        var quota: AIQuota?
        var error: String?
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "ngày không đọc được"))
            }
            return date
        }
        return decoder
    }()

    static func encode(_ request: AIRunRequest) throws -> Data {
        var trimmed = request
        trimmed.sheet = request.sheet.map { String($0.prefix(maxSheetLength)) }
        trimmed.text = request.text.map { String($0.prefix(maxTextLength)) }
        return try JSONEncoder().encode(trimmed)
    }

    static func runResponse(status: Int, data: Data) throws -> AIRunResponse {
        let body = try? decoder.decode(RunBody.self, from: data)
        switch status {
        case 200:
            guard let text = body?.text, let quota = body?.quota else { throw AIError.network }
            return AIRunResponse(text: text.trimmingCharacters(in: .whitespacesAndNewlines), quota: quota)
        case 401, 403: throw AIError.notSubscribed
        case 429: throw AIError.quotaExceeded(body?.quota)
        case 500...599: throw AIError.unavailable
        default: throw AIError.network
        }
    }

    static func quotaResponse(status: Int, data: Data) throws -> AIQuota {
        switch status {
        case 200:
            guard let quota = (try? decoder.decode(RunBody.self, from: data))?.quota else { throw AIError.network }
            return quota
        case 401, 403: throw AIError.notSubscribed
        case 500...599: throw AIError.unavailable
        default: throw AIError.network
        }
    }

    /// Dòng AI viết lại có dùng được không: một dòng ngắn, không rỗng. Nơi gọi còn phải cho bộ tách đọc lại rồi mới tin.
    static func cleanedLine(_ text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.count <= 200, !line.contains("\n") else { return nil }
        return line
    }
}
