import SwiftUI

/// Một dòng chữ trần: tên bên trái, số tiền bên phải.
struct ExpenseRow: View {
    let expense: Expense
    /// Danh mục hiện ở dòng phụ, kèm biểu tượng; nil thì không hiện (tra bằng `CategoryCatalog`).
    var category: CategoryInfo?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.displayName)
                    .font(.body)
                note
            }
            Spacer(minLength: 8)
            if let photo = expense.photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(.rect(cornerRadius: 6))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
                    .accessibilityLabel("có ảnh")
            }
            Text(MoneyFormatter.short(expense.amount))
                .font(.body.weight(.medium))
                .money(expense.amount)
        }
        .foregroundStyle(expense.isOutsideBudget ? Color.xuTextSecondary : Color.xuTextPrimary)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var rest: String? {
        let parts = [expense.foreignNote, expense.splitNote, expense.isOutsideBudget ? String(localized: "ngoài ngân sách") : nil].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var note: some View {
        if category != nil || rest != nil {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.symbol).accessibilityHidden(true)
                    Text(category.title)
                }
                if let rest {
                    Text(category == nil ? rest : "· \(rest)")
                }
            }
            .font(.caption)
            .foregroundStyle(Color.xuTextSecondary)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ExpenseRow(expense: PreviewData.expense, category: CategoryCatalog(custom: []).info(for: "food"))
        ExpenseRow(expense: Expense(name: "phở", amount: 45_000, categoryKey: "food"), category: CategoryCatalog(custom: []).info(for: "food"))
    }
    .padding()
    .xuScreen()
    .xuPreview()
}
