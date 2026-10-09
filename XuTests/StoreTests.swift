import StoreKit
import StoreKitTest
import Testing
@testable import Xu

/// Chạy với tệp cấu hình cục bộ `Xu.storekit`, không cần App Store Connect.
@Suite(.serialized) @MainActor
struct StoreTests {
    private func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Xu")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    /// Dịch vụ StoreKit thử nghiệm báo giao dịch trễ một nhịp, nhất là khi máy đang nặng tải.
    private func waitUntil(_ store: EntitlementStore, _ condition: (EntitlementStore) -> Bool) async {
        for _ in 0..<50 {
            await store.refresh()
            if condition(store) { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    @Test func bothPlansExistAndYearlyHasAWeekFree() async throws {
        _ = try session()
        let products = try await Product.products(for: EntitlementStore.productIDs)
        #expect(Set(products.map(\.id)) == [EntitlementStore.monthlyID, EntitlementStore.yearlyID])

        let yearly = try #require(products.first { $0.id == EntitlementStore.yearlyID })
        let offer = try #require(yearly.subscription?.introductoryOffer)
        #expect(offer.paymentMode == .freeTrial)
        #expect(offer.period.unit == .week)
        #expect(offer.period.value == 1)
        #expect(yearly.subscription?.subscriptionPeriod.unit == .year)

        let monthly = try #require(products.first { $0.id == EntitlementStore.monthlyID })
        #expect(monthly.subscription?.introductoryOffer == nil)
        #expect(monthly.subscription?.subscriptionGroupID == yearly.subscription?.subscriptionGroupID)
    }

    @Test func buyingUnlocksProAndClearingRevokesIt() async throws {
        let session = try session()
        let store = EntitlementStore()
        await store.refresh()
        #expect(!store.isPro)

        await store.loadProducts()
        #expect(store.products.map(\.id) == EntitlementStore.productIDs)

        try await session.buyProduct(identifier: EntitlementStore.yearlyID)
        await waitUntil(store) { $0.isPro }
        #expect(store.isPro)
        #expect(SaveGate.isPro)

        session.clearTransactions()
        await waitUntil(store) { !$0.isPro }
        #expect(!store.isPro)
        #expect(!SaveGate.isPro)
    }
}
