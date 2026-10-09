import SwiftUI

/// Một khoản trong phần xem trước, sau khi áp các chỗ người dùng đã sửa.
struct EntryRow: Identifiable, Equatable {
    let id: Int
    var name: String
    var loanPerson: String?
    var amount: Int?
    var categoryKey: String
    var originalAmount: Int?
    var splitCount: Int?
    var isOutsideBudget: Bool
    var teachesCategory = false

    var isLoan: Bool { loanPerson != nil }

    var recordItem: RecordItem? {
        guard let amount else { return nil }
        if let loanPerson { return .loan(person: loanPerson, amount: amount) }
        return .expense(ExpenseDraft(
            name: name, amount: amount, categoryKey: categoryKey,
            originalAmount: originalAmount, splitCount: splitCount,
            isOutsideBudget: isOutsideBudget, teachesCategory: teachesCategory
        ))
    }
}

/// Chỗ người dùng sửa tay trên một dòng xem trước. Chỉ áp khi tên khoản còn khớp.
struct EntryOverride: Equatable {
    var name: String
    var amount: Int?
    var categoryKey: String?
    var isOutsideBudget: Bool?
}

enum EntryRows {
    static func resolve(_ lines: [ParsedLine], overrides: [Int: EntryOverride], dailyAllowance: Int) -> [EntryRow] {
        var rows: [EntryRow] = []
        for line in lines {
            let id = rows.count
            switch line {
            case .question:
                continue
            case .loan(let person, let amount):
                rows.append(EntryRow(
                    id: id, name: String(localized: "ứng cho \(person)"), loanPerson: person, amount: amount,
                    categoryKey: SpendingCategory.other.rawValue, isOutsideBudget: true
                ))
            case .expense(let parsed):
                var row = EntryRow(
                    id: id, name: parsed.name, amount: parsed.amount, categoryKey: parsed.categoryKey,
                    originalAmount: parsed.originalAmount, splitCount: parsed.splitCount,
                    isOutsideBudget: parsed.isOutsideBudget
                )
                if let edit = overrides[id], edit.name == parsed.name {
                    if let amount = edit.amount, amount != parsed.amount {
                        row.amount = amount
                        row.originalAmount = nil
                        row.splitCount = nil
                        row.isOutsideBudget = ExpenseParser.isOutsideBudget(amount: amount, dailyAllowance: dailyAllowance)
                    }
                    if let categoryKey = edit.categoryKey, categoryKey != parsed.categoryKey {
                        row.categoryKey = categoryKey
                        row.teachesCategory = true
                    }
                    if let isOutsideBudget = edit.isOutsideBudget {
                        row.isOutsideBudget = isOutsideBudget
                    }
                }
                rows.append(row)
            }
        }
        return rows
    }
}

struct EntryRowView: View {
    let row: EntryRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name.isEmpty ? String(localized: "khoản chi") : row.name)
                HStack(spacing: 6) {
                    if row.isLoan {
                        Text("không tính vào chi tiêu")
                    } else {
                        Text(SpendingCategory(key: row.categoryKey).title)
                        if let originalAmount = row.originalAmount, let splitCount = row.splitCount {
                            Text("· \(MoneyFormatter.short(originalAmount)) chia \(splitCount)")
                        }
                        if row.isOutsideBudget {
                            ButterLabel(text: "ngoài ngân sách")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.xuTextSecondary)
            }
            Spacer(minLength: 8)
            if let amount = row.amount {
                Text(MoneyFormatter.short(amount))
                    .fontWeight(.medium)
                    .money(amount)
                    .foregroundStyle(row.isOutsideBudget ? Color.xuTextSecondary : Color.xuTextPrimary)
            } else {
                Text("thiếu số tiền")
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let lines = ExpenseParser().parse(
        "cơm tấm 55, tai nghe 1tr2, nhậu 460k chia 4, ứng cho Minh 200k, bánh", rules: [:], dailyAllowance: 300_000
    )
    VStack(spacing: 0) {
        ForEach(EntryRows.resolve(lines, overrides: [:], dailyAllowance: 300_000)) { EntryRowView(row: $0) }
    }
    .padding(24)
    .xuScreen()
    .xuPreview()
}
