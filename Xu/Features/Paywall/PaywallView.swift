import StoreKit
import SwiftUI

/// Xu Pro: quyền lợi, hai gói, dùng thử, khôi phục.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @Environment(EntitlementStore.self) private var store
    @State private var selectedID = EntitlementStore.yearlyID
    @State private var isWorking = false
    @State private var message: String?

    private var selected: Product? {
        store.products.first { $0.id == selectedID } ?? store.products.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HighlightedNumber(text: "Xu Pro", fraction: 1, size: 48)
                            .accessibilityAddTraits(.isHeader)
                        Text(store.isPro ? "Bạn đang dùng Xu Pro. Cảm ơn bạn." : "Bản miễn phí cho gõ 5 lần mỗi ngày.")
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(PaywallBenefit.current, id: \.self) { benefit in
                            Label(benefit, systemImage: "checkmark")
                        }
                    }
                    if !store.isPro {
                        plans
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                }
                .padding(24)
            }
            .xuScreen()
            .safeAreaInset(edge: .bottom) { actions }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task { await store.loadProducts() }
        }
        .fontDesign(.rounded)
    }

    // MARK: - Các gói

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            HStack {
                if store.isLoadingProducts {
                    ProgressView()
                    Text("Đang tải giá")
                } else {
                    Text("Chưa tải được giá từ App Store.")
                    Spacer()
                    Button("Thử lại") { Task { await store.loadProducts() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .foregroundStyle(Color.xuTextSecondary)
        } else {
            VStack(spacing: 10) {
                ForEach(store.products) { product in
                    let isSelected = product.id == selected?.id
                    Button { selectedID = product.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.id == EntitlementStore.yearlyID ? "Gói năm" : "Gói tháng")
                                    .font(.headline)
                                if hasFreeTrial(product) {
                                    Text("7 ngày đầu miễn phí")
                                        .font(.caption)
                                        .foregroundStyle(Color.xuTextSecondary)
                                }
                            }
                            Spacer()
                            Text(product.id == EntitlementStore.yearlyID
                                ? "\(product.displayPrice)/năm" : "\(product.displayPrice)/tháng")
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 60)
                        .background(isSelected ? Color.xuButton.opacity(0.45) : Color.xuSurface, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func hasFreeTrial(_ product: Product) -> Bool {
        product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    // MARK: - Nút

    private var actions: some View {
        VStack(spacing: 4) {
            if !store.isPro, let selected {
                Button(hasFreeTrial(selected) ? "Dùng thử 7 ngày miễn phí" : "Đăng ký \(selected.displayPrice)") {
                    buy(selected)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
            }
            Button("Khôi phục giao dịch") {
                Task {
                    isWorking = true
                    await store.restore()
                    isWorking = false
                    message = store.isPro ? nil : String(localized: "Không tìm thấy giao dịch Xu Pro nào để khôi phục.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.xuTextSecondary)
            .frame(minHeight: 44)
            .disabled(isWorking)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .background(Color.xuBackground)
    }

    private func buy(_ product: Product) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                if await store.process(try await purchase(product)) { dismiss() }
            } catch {
                message = String(localized: "Chưa mua được. Bạn thử lại sau nhé.")
            }
        }
    }
}

enum PaywallBenefit {
    /// Chỉ liệt kê quyền lợi đã có trong bản này.
    @MainActor static var current: [String] {
        [
            String(localized: "Gõ không giới hạn"),
            String(localized: "Chụp hóa đơn"),
            String(localized: "Widget màn hình khóa"),
        ]
    }
}

#Preview {
    PaywallView().xuPreview()
}
