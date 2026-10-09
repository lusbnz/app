import SwiftData
import SwiftUI

extension View {
    /// Hỏi có áp luật danh mục vừa lưu cho các khoản cũ không.
    func reapplyDialog(_ offer: Binding<ReapplyOffer?>) -> some View {
        modifier(ReapplyDialog(offer: offer))
    }
}

private struct ReapplyDialog: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Query private var customCategories: [CustomCategory]
    @Binding var offer: ReapplyOffer?

    func body(content: Content) -> some View {
        let title = offer.map { "Áp cho \($0.count) khoản trước đây?" } ?? ""
        content.confirmationDialog(
            LocalizedStringKey(title), isPresented: Binding { offer != nil } set: { if !$0 { offer = nil } },
            titleVisibility: .visible, presenting: offer
        ) { offer in
            Button("Chuyển \(offer.count) khoản") {
                ExpenseRecorder(context: modelContext).apply(offer)
            }
            Button("Chỉ từ nay", role: .cancel) {}
        } message: { offer in
            let category = CategoryCatalog(custom: customCategories).info(for: offer.categoryKey).title
            Text("Các khoản có tên “\(offer.keyword)” sẽ chuyển sang \(category).")
        }
    }
}
