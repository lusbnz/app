import Foundation

/// Địa chỉ Worker của gói AI. Chưa đặt (nil) thì mọi giao diện AI đều ẩn và app không gọi mạng.
/// Triển khai `Backend/` rồi điền địa chỉ vào đây, ví dụ `URL(string: "https://pennyline-ai.<tên>.workers.dev")`.
enum AIConfig {
    static let productionURL: URL? = nil

    static var baseURL: URL? {
        #if DEBUG
        // Thử với Worker chạy cục bộ: thêm tham số khởi chạy `-aiBaseURL http://localhost:8787`.
        if let text = UserDefaults.standard.string(forKey: "aiBaseURL"), let url = URL(string: text) { return url }
        #endif
        return productionURL
    }
}

/// Nơi trả lời cho gói AI; có bản thật (`AIClient`) và bản giả cho test, xem trước.
protocol AIServing: Sendable {
    func run(_ request: AIRunRequest) async throws -> AIRunResponse
    func quota() async throws -> AIQuota
    /// Báo một giao dịch nạp thêm lượt để Worker kiểm với Apple rồi cộng lượt.
    func topUp(transactionID: String) async throws -> AIQuota
}

/// Gọi Worker. Mỗi yêu cầu mang mã giao dịch của gói AI; Worker tự hỏi Apple xem gói còn hiệu lực không.
struct AIClient: AIServing {
    let baseURL: URL
    /// Mã giao dịch của gói AI đang chạy.
    let transactionID: String
    var session: URLSession = .shared

    private func request(_ path: String, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(transactionID, forHTTPHeaderField: AIProtocol.transactionHeader)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Int, Data) {
        do {
            let (data, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw AIError.network
        }
    }

    func run(_ request: AIRunRequest) async throws -> AIRunResponse {
        let (status, data) = try await send(self.request("v1/run", method: "POST", body: AIProtocol.encode(request)))
        return try AIProtocol.runResponse(status: status, data: data)
    }

    func quota() async throws -> AIQuota {
        let (status, data) = try await send(request("v1/quota", method: "GET"))
        return try AIProtocol.quotaResponse(status: status, data: data)
    }

    func topUp(transactionID: String) async throws -> AIQuota {
        let body = try JSONEncoder().encode(["transactionId": transactionID])
        let (status, data) = try await send(request("v1/topup", method: "POST", body: body))
        return try AIProtocol.quotaResponse(status: status, data: data)
    }
}
