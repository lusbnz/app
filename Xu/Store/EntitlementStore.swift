import Observation
import StoreKit

/// Trạng thái Xu Pro, đọc từ StoreKit 2.
@MainActor @Observable
final class EntitlementStore {
    static let shared = EntitlementStore()

    static let monthlyID = "xu.pro.monthly"
    static let yearlyID = "xu.pro.yearly"
    static let productIDs = [yearlyID, monthlyID]

    private(set) var isPro = SaveGate.isPro
    /// Gói năm đứng trước.
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    @ObservationIgnored private var updates: Task<Void, Never>?

    /// Bắt đầu lắng nghe giao dịch. Gọi một lần khi app mở.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProducts()
        }
    }

    #if DEBUG
    @ObservationIgnored private var isGrantedForDebug = false

    /// Mở Xu Pro không qua StoreKit, chỉ cho tham số khởi chạy `-pro` của bản Debug.
    func grantForDebug() {
        isGrantedForDebug = true
        isPro = true
        SaveGate.isPro = true
    }
    #endif

    func refresh() async {
        #if DEBUG
        if isGrantedForDebug { return }
        #endif
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        guard active != isPro || active != SaveGate.isPro else { return }
        isPro = active
        SaveGate.isPro = active
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let loaded = (try? await Product.products(for: Self.productIDs)) ?? []
        products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
    }

    /// Xử lý kết quả mua. Trả về true khi đã có Xu Pro.
    @discardableResult
    func process(_ result: Product.PurchaseResult) async -> Bool {
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
        }
        await refresh()
        return isPro
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
