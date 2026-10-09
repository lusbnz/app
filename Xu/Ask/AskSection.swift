import SwiftUI

/// Khối Hỏi Xu ở đáy màn hình Tháng. Phần hỏi đáp được nối ở giai đoạn 8.
struct AskSection: View {
    let snapshot: SpendingSnapshot

    var body: some View {
        EmptyView()
    }
}

#Preview {
    AskSection(snapshot: SpendingSnapshot.make(records: [], monthlyBudget: 9_000_000, now: Date(), calendar: .current))
        .xuPreview()
}
