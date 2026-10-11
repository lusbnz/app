import StoreKit
import SwiftUI

/// Pennyline AI: gói riêng, tính theo lượt dùng mỗi tháng. Nói rõ thứ gì được gửi đi, xin đồng ý, mua gói và xem số lượt còn lại.
struct AISettingsView: View {
    @State private var ai = AIStore.shared
    @State private var isBuying = false

    var body: some View {
        List {
            Section {
                Toggle("Cho phép gửi số liệu tới Claude", isOn: $ai.hasConsent)
            } header: {
                Text("Quyền riêng tư")
            } footer: {
                Text("Khi bạn dùng một việc AI, Pennyline gửi bảng số liệu tháng đã gộp sẵn (tổng theo danh mục, theo tên khoản, theo ngày) hoặc đúng dòng chữ bạn nhờ AI hiểu tới máy chủ của Pennyline, rồi tới Claude của Anthropic để lấy câu trả lời. Không gửi ảnh, vị trí hay từng khoản chi riêng lẻ, và máy chủ không lưu nội dung. Tắt công tắc này thì không có gì được gửi, kể cả khi đã mua gói.")
            }
            .listRowBackground(Color.xuSurface)

            Section {
                if ai.isSubscribed {
                    if let quota = ai.quota {
                        row("Còn lại tháng này", String(localized: "\(quota.remaining) lượt"))
                        row("Đã dùng", "\(quota.used)/\(quota.limit)")
                        if quota.credits > 0 { row("Lượt nạp thêm", "\(quota.credits)") }
                        row("Làm mới", VietnameseDate.dayTitle(quota.resetsAt, calendar: .current))
                    } else if ai.lastError != nil {
                        Text("Chưa lấy được số lượt. Kiểm tra mạng rồi thử lại.")
                            .foregroundStyle(Color.xuTextSecondary)
                    } else {
                        Text(ai.hasConsent ? "Đang lấy số lượt…" : "Bật công tắc ở trên để bắt đầu dùng.")
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    if let topUp = product(AIStore.topUpID) {
                        buyButton(topUp, title: "Nạp thêm lượt")
                    }
                } else if let monthly = product(AIStore.monthlyID) {
                    buyButton(monthly, title: "Đăng ký Pennyline AI")
                } else {
                    Text("Chưa tải được gói. Kiểm tra mạng rồi thử lại.")
                        .foregroundStyle(Color.xuTextSecondary)
                }
            } header: {
                Text("Gói và lượt dùng")
            } footer: {
                Text("Mỗi lần hỏi, mỗi lần nhận xét tháng và mỗi lần nhờ AI hiểu một câu tính một lượt. Lượt của gói làm mới đầu mỗi tháng; lượt nạp thêm không hết hạn. Gói AI tách khỏi Pennyline Pro.")
            }
            .listRowBackground(Color.xuSurface)

            Section {
                Label("Hỏi Pennyline trên máy chưa có mô hình của Apple", systemImage: "bubble.left.and.text.bubble.right")
                Label("Nhận xét tháng ở màn Tháng", systemImage: "text.quote")
                Label("Hiểu câu gõ tự nhiên ở ô gõ", systemImage: "wand.and.stars")
            } header: {
                Text("AI làm gì")
            } footer: {
                Text("Con số luôn do Pennyline tính. AI chỉ diễn đạt, và câu trả lời có con số lạ sẽ bị bỏ.")
            }
            .listRowBackground(Color.xuSurface)
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Pennyline AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await ai.loadProducts()
            await ai.refresh()
        }
        .onChange(of: ai.hasConsent) { Task { await ai.refreshQuota() } }
    }

    private func product(_ id: String) -> Product? {
        ai.products.first { $0.id == id }
    }

    private func buyButton(_ product: Product, title: LocalizedStringKey) -> some View {
        Button {
            isBuying = true
            Task {
                await ai.purchase(product)
                isBuying = false
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: product.displayPrice).foregroundStyle(Color.xuTextSecondary)
            }
        }
        .disabled(isBuying)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(Color.xuTextSecondary)
        }
    }
}

/// Nhận xét tháng bằng gói AI, ở màn Tháng. Chỉ hiện khi gói đang dùng được; bấm mới gọi (mỗi lần một lượt).
struct AIInsightCard: View {
    @Environment(\.calendar) private var calendar
    @State private var ai = AIStore.shared
    @State private var text: String?
    @State private var isLoading = false
    @State private var failure: String?
    let snapshot: SpendingSnapshot

    var body: some View {
        if ai.isActive {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nhận xét tháng này")
                    .font(.subheadline.weight(.semibold))
                if let text {
                    Text(verbatim: text)
                } else if let failure {
                    Text(verbatim: failure).foregroundStyle(Color.xuTextSecondary)
                }
                if isLoading {
                    ProgressView()
                } else {
                    Button(text == nil ? "Viết nhận xét" : "Viết lại") { load() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() {
        isLoading = true
        failure = nil
        let sheet = SpendingFacts.sheet(snapshot, calendar: calendar) { key in
            snapshot.categoryNames[key] ?? String(localized: SpendingCategory(key: key).title)
        }
        Task {
            defer { isLoading = false }
            do {
                let answer = try await ai.run(AIRunRequest(task: .insight, sheet: sheet, language: AILanguage.current))
                // Cùng luật với Hỏi Pennyline: có con số không nằm trong bảng số liệu thì bỏ.
                if !answer.isEmpty, SpendingFacts.usesOnlyKnownNumbers(answer, sheet: sheet, question: "") {
                    text = answer
                } else {
                    failure = AIText.message(for: .unavailable)
                }
            } catch {
                failure = AIText.message(for: error as? AIError ?? .network)
            }
        }
    }
}

enum AIText {
    static func message(for error: AIError) -> String {
        switch error {
        case .quotaExceeded: String(localized: "Hết lượt AI của tháng này. Nạp thêm trong Tùy chỉnh, Pennyline AI.")
        case .notSubscribed, .notConfigured: String(localized: "Gói Pennyline AI chưa dùng được. Xem trong Tùy chỉnh, Pennyline AI.")
        case .unavailable: String(localized: "AI chưa trả lời chắc được lần này, lượt đã được trả lại. Bạn thử lại sau nhé.")
        case .network: String(localized: "Không kết nối được tới AI. Kiểm tra mạng rồi thử lại.")
        }
    }
}

#Preview {
    NavigationStack { AISettingsView() }.xuPreview()
}
