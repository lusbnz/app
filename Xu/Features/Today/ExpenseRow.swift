import SwiftUI

/// Một dòng chữ trần: tên bên trái, số tiền bên phải.
struct ExpenseRow: View {
    let expense: Expense
    /// Tên danh mục hiện ở dòng phụ; nil thì không hiện (xem `CategoryCatalog`).
    var categoryTitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.displayName)
                    .font(.body)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color.xuTextSecondary)
                }
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

    private var note: String? {
        let parts = [categoryTitle, expense.splitNote, expense.isOutsideBudget ? String(localized: "ngoài ngân sách") : nil]
            .compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    VStack(spacing: 0) {
        ExpenseRow(expense: PreviewData.expense, categoryTitle: "ăn uống")
        ExpenseRow(expense: Expense(name: "phở", amount: 45_000, categoryKey: "food"), categoryTitle: "ăn uống")
    }
    .padding()
    .xuScreen()
    .xuPreview()
}
