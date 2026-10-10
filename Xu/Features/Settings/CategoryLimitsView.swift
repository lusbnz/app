import SwiftData
import SwiftUI

/// Hạn mức tháng cho từng danh mục. Chỉ để cảnh báo, không đổi "hôm nay còn bao nhiêu".
struct CategoryLimitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var customCategories: [CustomCategory]
    @Query private var budgets: [CategoryBudget]

    var body: some View {
        let limits = budgets.lookup
        List {
            Section {
                ForEach(CategoryCatalog(custom: customCategories).all) { category in
                    LimitRow(title: category.title, current: limits[category.key]) { amount in
                        ExpenseRecorder(context: modelContext).setLimit(categoryKey: category.key, amount: amount)
                    }
                }
            } footer: {
                Text("Khi một danh mục dùng từ 80% hạn mức hoặc vượt, Nhẩm báo lúc bạn ghi và ở màn Tháng. Hạn mức mỗi ngày vẫn tính từ ngân sách tháng. Để trống nghĩa là không đặt hạn mức.")
            }
            .listRowBackground(Color.xuSurface)
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Hạn mức danh mục")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LimitRow: View {
    let title: String
    let current: Int?
    let commit: (Int?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("không đặt", text: $text)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(save)
                .frame(maxWidth: 140)
                .accessibilityLabel("Hạn mức \(title)")
        }
        .frame(minHeight: 44)
        .onAppear(perform: reset)
        .onChange(of: current) { if !focused { reset() } }
        .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
    }

    private func reset() {
        text = current.map(MoneyFormatter.full) ?? ""
    }

    /// Để trống là bỏ hạn mức; chữ không đọc được thì giữ hạn mức cũ.
    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if current != nil { commit(nil) }
        } else if let amount = BudgetInput.parse(trimmed), amount != current {
            commit(amount)
        }
        reset()
    }
}

#Preview {
    NavigationStack { CategoryLimitsView() }
        .xuPreview()
}
