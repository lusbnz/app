import Foundation
import Observation
import StoreKit

/// Trạng thái gói Pennyline AI: đã đặt địa chỉ Worker chưa, người dùng đã mua và đã đồng ý gửi số liệu chưa, còn bao nhiêu lượt.
/// Gói AI tách khỏi Pennyline Pro: mua gói này không mở Pro và ngược lại.
@MainActor @Observable
final class AIStore {
    static let shared = AIStore()

    static let monthlyID = "xu.ai.monthly"
    static let topUpID = "xu.ai.topup"
    private static let consentKey = "aiConsent"
    /// Đọc được từ ngoài luồng chính (`AskEngine`), nên lưu thành một cờ trong App Group.
    nonisolated private static let activeKey = "aiActive"

    private(set) var isSubscribed = false
    private(set) var products: [Product] = []
    private(set) var quota: AIQuota?
    /// Lỗi gần nhất khi hỏi số lượt, để màn cài đặt nói rõ.
    private(set) var lastError: AIError?
    /// Người dùng đồng ý gửi bảng số liệu và câu chữ tới Claude. Không đồng ý thì không gọi mạng dù đã mua.
    var hasConsent: Bool {
        didSet {
            AppGroup.defaults.set(hasConsent, forKey: Self.consentKey)
            publish()
        }
    }

    @ObservationIgnored private var transactionID: String?
    @ObservationIgnored private var override: (any AIServing)?

    init() {
        hasConsent = AppGroup.defaults.bool(forKey: Self.consentKey)
    }

    /// Đã đặt địa chỉ Worker (hoặc đang dùng bản giả để thử).
    var isConfigured: Bool { override != nil || AIConfig.baseURL != nil }

    /// Dùng được ngay: có Worker, có gói, đã đồng ý.
    var isActive: Bool { isConfigured && isSubscribed && hasConsent }

    /// Như `isActive`, đọc được từ mọi luồng.
    nonisolated static var isActiveAnywhere: Bool { AppGroup.defaults.bool(forKey: activeKey) }

    var client: (any AIServing)? {
        if let override { return override }
        guard let baseURL = AIConfig.baseURL, let transactionID else { return nil }
        return AIClient(baseURL: baseURL, transactionID: transactionID)
    }

    private func publish() {
        AppGroup.defaults.set(isActive, forKey: Self.activeKey)
    }

    /// Đọc lại gói đang có từ StoreKit, rồi hỏi số lượt còn lại.
    func refresh() async {
        guard override == nil else { return }
        var found: String?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.productID == Self.monthlyID, transaction.revocationDate == nil {
                found = String(transaction.id)
            }
        }
        transactionID = found
        isSubscribed = found != nil
        publish()
        await refreshQuota()
    }

    func refreshQuota() async {
        guard isActive, let client else { return }
        do {
            quota = try await client.quota()
            lastError = nil
        } catch {
            lastError = error as? AIError ?? .network
        }
    }

    func loadProducts() async {
        guard products.isEmpty, AIConfig.baseURL != nil else { return }
        let loaded = (try? await Product.products(for: [Self.monthlyID, Self.topUpID])) ?? []
        products = [Self.monthlyID, Self.topUpID].compactMap { id in loaded.first { $0.id == id } }
    }

    /// Mua gói tháng hoặc nạp thêm lượt. Lượt nạp thêm chỉ được tính sau khi Worker kiểm giao dịch với Apple.
    func purchase(_ product: Product) async {
        guard case .success(.verified(let transaction))? = try? await product.purchase() else { return }
        if product.id == Self.topUpID, let client {
            // Chưa báo được cho Worker thì chưa kết thúc giao dịch, để lần mở app sau thử lại.
            guard let updated = try? await client.topUp(transactionID: String(transaction.id)) else { return }
            quota = updated
        }
        await transaction.finish()
        await refresh()
    }

    /// Gọi một việc AI và cập nhật số lượt còn lại.
    func run(_ request: AIRunRequest) async throws -> String {
        guard isActive, let client else { throw isConfigured ? AIError.notSubscribed : AIError.notConfigured }
        do {
            let response = try await client.run(request)
            quota = response.quota
            return response.text
        } catch let error as AIError {
            if case .quotaExceeded(let latest) = error, let latest { quota = latest }
            throw error
        }
    }

    #if DEBUG
    /// Cờ chạy thử `-ai`: coi như đã đặt Worker, đã mua và đã đồng ý, trả lời bằng bản giả.
    func enableDebugStub(_ stub: any AIServing) {
        override = stub
        isSubscribed = true
        hasConsent = true
        publish()
        Task { quota = try? await stub.quota() }
    }
    #endif
}
