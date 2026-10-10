import SwiftData
import SwiftUI

/// Khoản định kỳ (tiền nhà, Netflix): thêm, sửa, xóa. Đến hạn Pennyline nhắc, người dùng chạm mới ghi.
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
                                Text("\(item.scheduleText(calendar: calendar)) · \(catalog.info(for: item.categoryKey).title)\(item.isOutsideBudget ? " · ngoài ngân sách" : "")\(item.autoRecord ? " · tự ghi" : "")")
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
                Text("Đến hạn, Pennyline nhắc lúc 9:00 và hiện khoản đó ở màn Hôm nay. Mặc định bạn chạm Ghi thì mới ghi; khoản nào bật “Tự ghi” thì Pennyline ghi khi bạn mở app.")
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
    @State private var frequency = RecurringFrequency.monthly
    @State private var weekday = 2
    @State private var month = 1
    @State private var autoRecord = false

    private var amount: Int? { fields.amount.flatMap { $0 > 0 ? $0 : nil } }
    private var name: String { fields.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ExpenseFieldsEditor(fields: $fields, showsDate: false)
                    Picker("Lặp lại", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 8)
                    switch frequency {
                    case .weekly:
                        scheduleRow("Thứ") {
                            Picker("Thứ", selection: $weekday) {
                                // Bắt đầu từ thứ Hai cho người dùng Việt; giá trị vẫn theo Calendar.weekday.
                                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { value in
                                    Text(calendar.weekdaySymbols[value - 1]).tag(value)
                                }
                            }
                            .labelsHidden()
                        }
                    case .monthly:
                        scheduleRow("Ngày trong tháng") { dayPicker }
                    case .yearly:
                        scheduleRow("Tháng") {
                            Picker("Tháng", selection: $month) {
                                ForEach(1...12, id: \.self) { Text("Tháng \($0)").tag($0) }
                            }
                            .labelsHidden()
                        }
                        scheduleRow("Ngày") { dayPicker }
                    }
                    Toggle("Tự ghi khi đến hạn", isOn: $autoRecord)
                        .frame(minHeight: 52)
                    Text(autoRecord
                         ? "Pennyline ghi khi bạn mở app sau ngày đến hạn, vẫn tính vào 5 lần ghi mỗi ngày của bản miễn phí. Ghi nhầm thì xóa hoặc sửa như khoản thường."
                         : "Tháng nào không có ngày này thì tính vào ngày cuối tháng. Pennyline nhắc lúc 9:00 và bạn chạm Ghi.")
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
                frequency = item.frequency
                weekday = item.weekday
                month = item.monthOfYear
                autoRecord = item.autoRecord
            }
        }
        .fontDesign(.rounded)
    }

    private var dayPicker: some View {
        Picker("Ngày", selection: $day) {
            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
        }
        .labelsHidden()
    }

    private func scheduleRow(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
        .frame(minHeight: 52)
    }

    private func save() {
        guard let amount else { return }
        let recorder = ExpenseRecorder(context: modelContext)
        if let item = form.editing {
            recorder.updateRecurring(
                item, name: name, amount: amount, categoryKey: fields.categoryKey, dayOfMonth: day,
                isOutsideBudget: fields.isOutsideBudget,
                frequency: frequency, weekday: weekday, monthOfYear: month, autoRecord: autoRecord
            )
        } else {
            recorder.addRecurring(
                name: name, amount: amount, categoryKey: fields.categoryKey, dayOfMonth: day,
                isOutsideBudget: fields.isOutsideBudget, now: Date(),
                frequency: frequency, weekday: weekday, monthOfYear: month, autoRecord: autoRecord
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
