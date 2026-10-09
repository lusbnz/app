import SwiftData
import SwiftUI

/// Khoản định kỳ (tiền nhà, Netflix): thêm, sửa, xóa. Đến hạn Xu nhắc, người dùng chạm mới ghi.
struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query(sort: \RecurringExpense.createdAt) private var items: [RecurringExpense]
    @Query private var customCategories: [CustomCategory]
    @State private var form: RecurringForm?

    var body: some View {
        let catalog = CategoryCatalog(custom: customCategories)
        List {
            Section {
                ForEach(items) { item in
                    Button { form = RecurringForm(editing: item) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(Color.xuTextPrimary)
                                Text("ngày \(item.dayOfMonth) · \(catalog.info(for: item.categoryKey).title)\(item.isOutsideBudget ? " · ngoài ngân sách" : "")")
                                    .font(.caption)
                                    .foregroundStyle(Color.xuTextSecondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.short(item.amount)).foregroundStyle(Color.xuTextSecondary)
                        }
                    }
                    .swipeActions {
                        Button("Xóa", role: .destructive) {
                            ExpenseRecorder(context: modelContext).deleteRecurring(item)
                        }
                    }
                }
                Button("Thêm khoản định kỳ") { form = RecurringForm(editing: nil) }
            } footer: {
                Text("Đến ngày, Xu nhắc lúc 9:00 và hiện khoản đó ở màn Hôm nay. Bạn chạm Ghi thì mới ghi, Xu không tự trừ tiền.")
            }
            .listRowBackground(Color.xuSurface)
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Khoản định kỳ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $form) { form in
            RecurringEditor(form: form)
        }
    }
}

struct RecurringForm: Identifiable {
    let id = UUID()
    var editing: RecurringExpense?
}

/// Thêm hoặc sửa một khoản định kỳ.
struct RecurringEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    let form: RecurringForm
    @State private var fields = ExpenseFields(categoryKey: SpendingCategory.bills.rawValue)
    @State private var day = 1

    private var amount: Int? { fields.amount.flatMap { $0 > 0 ? $0 : nil } }
    private var name: String { fields.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ExpenseFieldsEditor(fields: $fields, showsDate: false)
                    HStack {
                        Text("Ngày trong tháng")
                        Spacer()
                        Picker("Ngày trong tháng", selection: $day) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                    }
                    .frame(minHeight: 52)
                    Text("Tháng nào không có ngày này thì tính vào ngày cuối tháng. Xu nhắc lúc 9:00.")
                        .font(.footnote)
                        .foregroundStyle(Color.xuTextSecondary)
                }
                .padding(.horizontal, 24)
            }
            .xuScreen()
            .navigationTitle(form.editing == nil ? "Khoản định kỳ mới" : "Sửa khoản định kỳ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu", action: save).disabled(name.isEmpty || amount == nil)
                }
            }
            .onAppear {
                guard let item = form.editing else { return }
                fields = ExpenseFields(
                    name: item.name, amountText: ExpenseFields.amountText(for: item.amount),
                    categoryKey: item.categoryKey, isOutsideBudget: item.isOutsideBudget
                )
                day = item.dayOfMonth
            }
        }
        .fontDesign(.rounded)
    }

    private func save() {
        guard let amount else { return }
        let recorder = ExpenseRecorder(context: modelContext)
        if let item = form.editing {
            recorder.updateRecurring(
                item, name: name, amount: amount, categoryKey: fields.categoryKey, dayOfMonth: day,
                isOutsideBudget: fields.isOutsideBudget
            )
        } else {
            recorder.addRecurring(
                name: name, amount: amount, categoryKey: fields.categoryKey, dayOfMonth: day,
                isOutsideBudget: fields.isOutsideBudget, now: Date()
            )
        }
        // Chỉ xin quyền thông báo khi người dùng thật sự đặt một khoản cần nhắc.
        Task { _ = await NotificationManager.shared.requestAuthorization() }
        dismiss()
    }
}

#Preview {
    NavigationStack { RecurringView() }
        .xuPreview()
}
