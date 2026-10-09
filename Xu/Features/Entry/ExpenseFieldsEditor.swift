import SwiftUI

/// Các trường sửa được của một khoản chi, dùng chung cho ô gõ, hóa đơn và Chi tiết.
struct ExpenseFields: Equatable {
    var name = ""
    var amountText = ""
    var categoryKey = SpendingCategory.other.rawValue
    var isOutsideBudget = false
    var date = Date()

    var amount: Int? { AmountParser.amount(from: amountText) }

    static func amountText(for amount: Int?) -> String {
        amount.map(MoneyFormatter.grouped) ?? ""
    }
}

struct ExpenseFieldsEditor: View {
    @Binding var fields: ExpenseFields
    var showsName = true
    var showsDate = true

    var body: some View {
        VStack(spacing: 0) {
            if showsName {
                row("Tên") {
                    TextField("phở", text: $fields.name)
                        .multilineTextAlignment(.trailing)
                }
            }
            row("Số tiền") {
                TextField("45k", text: $fields.amountText)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Danh mục")
                CategoryChips(selection: $fields.categoryKey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            Divider().overlay(Color.xuDivider)
            if showsDate {
                row("Thời gian") {
                    DatePicker("Thời gian", selection: $fields.date, in: ...Date())
                        .labelsHidden()
                }
            }
            Toggle("Ngoài ngân sách", isOn: $fields.isOutsideBudget)
                .frame(minHeight: 52)
        }
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                content()
            }
            .frame(minHeight: 52)
            Divider().overlay(Color.xuDivider)
        }
    }
}

/// Hàng danh mục cuộn ngang, chạm để chọn.
struct CategoryChips: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpendingCategory.allCases) { category in
                    let isSelected = category.rawValue == selection
                    Button { selection = category.rawValue } label: {
                        Text(category.title)
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? Color.xuOnButton : Color.xuTextPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(isSelected ? Color.xuButton : Color.xuSurface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }
}

#Preview {
    @Previewable @State var fields = ExpenseFields(name: "phở", amountText: "45.000", categoryKey: "food")
    ExpenseFieldsEditor(fields: $fields)
        .padding(24)
        .xuScreen()
        .xuPreview()
}
