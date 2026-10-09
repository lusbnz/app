import SwiftUI

/// Một khoản định kỳ đã đến hạn: chạm "Ghi" để ghi, hoặc "Bỏ qua" tháng này.
struct DueRecurringRow: View {
    let item: RecurringExpense
    let record: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text("đến hạn ngày \(item.dayOfMonth) · mỗi tháng")
                        .font(.caption)
                        .foregroundStyle(Color.xuTextSecondary)
                }
                Spacer(minLength: 8)
                Text(MoneyFormatter.short(item.amount))
                    .font(.body.weight(.medium))
                    .money(item.amount)
            }
            HStack(spacing: 8) {
                Button("Ghi", action: record)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Ghi \(item.name) \(MoneyFormatter.spoken(item.amount))")
                Button("Bỏ qua", action: skip)
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("Bỏ qua \(item.name) tháng này")
            }
        }
        .padding(14)
        .background(Color.xuSurface, in: .rect(cornerRadius: 18))
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    DueRecurringRow(
        item: RecurringExpense(name: "tiền nhà", amount: 3_000_000, categoryKey: "bills", dayOfMonth: 5),
        record: {}, skip: {}
    )
    .padding()
    .xuScreen()
}
