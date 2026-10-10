import Observation
import StoreKit

/// Trạng thái Pennyline Pro, đọc từ StoreKit 2.
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

    /// Bật hoặc tắt Pennyline Pro để thử (công tắc ở mục "Thử nghiệm" trong Tùy chỉnh, chỉ bản Debug). Tắt thì quay về
    /// trạng thái thật theo StoreKit.
    func setDebugPro(_ on: Bool) async {
        if on {
            grantForDebug()
        } else {
            isGrantedForDebug = false
            isPro = false
            SaveGate.isPro = false
            ThemeStore.shared.proUnlocked = false
            await refresh()
        }
    }

    /// Mở Pennyline Pro không qua StoreKit, chỉ cho tham số khởi chạy `-pro` của bản Debug.
    func grantForDebug() {
        isGrantedForDebug = true
        isPro = true
        SaveGate.isPro = true
        ThemeStore.shared.proUnlocked = true
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
        ThemeStore.shared.proUnlocked = active
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let loaded = (try? await Product.products(for: Self.productIDs)) ?? []
        products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
    }

    /// Xử lý kết quả mua. Trả về true khi đã có Pennyline Pro.
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
