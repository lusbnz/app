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
                                Text(subtitle(of: item, catalog: catalog))
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
        #if DEBUG
        .task {
            // Cờ chạy thử `-recurring N`: mở luôn màn sửa của khoản thứ N.
            guard let index = AppState.shared.debugRecurringIndex else { return }
            AppState.shared.debugRecurringIndex = nil
            try? await Task.sleep(for: .milliseconds(500))
            form = RecurringForm(editing: items.indices.contains(index) ? items[index] : nil)
        }
        #endif
    }
}

extension RecurringView {
    /// "ngày 5 hàng tháng · hóa đơn · ngoài ngân sách · tự ghi"
    fileprivate func subtitle(of item: RecurringExpense, catalog: CategoryCatalog) -> String {
        var parts = [item.scheduleText(calendar: calendar), catalog.info(for: item.categoryKey).title]
        if item.isOutsideBudget { parts.append(String(localized: "ngoài ngân sách")) }
        if item.autoRecord { parts.append(String(localized: "tự ghi")) }
        return parts.joined(separator: " · ")
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
    @State private var remindDayBefore = false

    private var amount: Int? { fields.amount.flatMap { $0 > 0 ? $0 : nil } }
    private var name: String { fields.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ExpenseFieldsEditor(fields: $fields, showsDate: false)
                    scheduleRow("Lặp lại") {
                        Picker("Lặp lại", selection: $frequency) {
                            ForEach(RecurringFrequency.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    switch frequency {
                    case .weekly, .biweekly:
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
                    case .quarterly:
                        scheduleRow("Ngày") { dayPicker }
                        scheduleRow("Các tháng") {
                            Picker("Các tháng", selection: quarterPhase) {
                                ForEach(1...3, id: \.self) { phase in
                                    Text(RecurringPlanner.quarterMonths(startingAt: phase).map(String.init).joined(separator: ", ")).tag(phase)
                                }
                            }
                            .labelsHidden()
                        }
                    case .yearly:
                        scheduleRow("Tháng") {
                            Picker("Tháng", selection: $month) {
                                ForEach(1...12, id: \.self) { Text("Tháng \($0)").tag($0) }
                            }
                            .labelsHidden()
                        }
                        scheduleRow("Ngày") { dayPicker }
                    }
                    if let due = nextDue {
                        scheduleRow("Lần tới") {
                            Text(VietnameseDate.dayTitle(due, calendar: calendar))
                                .foregroundStyle(Color.xuTextSecondary)
                        }
                    }
                    Toggle("Nhắc trước một ngày", isOn: $remindDayBefore)
                        .frame(minHeight: 52)
                    Toggle("Tự ghi khi đến hạn", isOn: $autoRecord)
                        .frame(minHeight: 52)
                    Text(footer)
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
            .onChange(of: frequency) {
                // Khoản mới mỗi quý: mặc định các tháng có tháng này, để lần tới không bị đẩy xa quá cần.
                if form.editing == nil, frequency == .quarterly { month = calendar.component(.month, from: Date()) }
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
                remindDayBefore = item.remindDayBefore
            }
        }
        .fontDesign(.rounded)
    }

    private var footer: LocalizedStringKey {
        if autoRecord {
            return "Pennyline ghi khi bạn mở app sau ngày đến hạn, vẫn tính vào 5 lần ghi mỗi ngày của bản miễn phí. Ghi nhầm thì xóa hoặc sửa như khoản thường."
        }
        switch frequency {
        case .weekly:
            return "Pennyline nhắc lúc 9:00 và bạn chạm Ghi."
        case .biweekly:
            return "Cứ hai tuần một lần, tính từ thứ đã chọn đầu tiên kể từ ngày tạo khoản. Pennyline nhắc lúc 9:00 và bạn chạm Ghi."
        case .monthly, .quarterly, .yearly:
            return "Tháng nào không có ngày này thì tính vào ngày cuối tháng. Pennyline nhắc lúc 9:00 và bạn chạm Ghi."
        }
    }

    /// Khoản mỗi quý chỉ có ba kiểu: 1-4-7-10, 2-5-8-11 hoặc 3-6-9-12; lưu tháng đầu của kiểu đã chọn.
    private var quarterPhase: Binding<Int> {
        Binding(get: { (month - 1) % 3 + 1 }, set: { month = $0 })
    }

    /// Ngày đến hạn kế tiếp theo lịch đang đặt, để người dùng thấy lịch mình chọn rơi vào đâu.
    private var nextDue: Date? {
        let editing = form.editing
        let item = RecurringItem(
            id: editing?.id ?? UUID(), name: name, amount: amount ?? 0, categoryKey: fields.categoryKey, dayOfMonth: day,
            isOutsideBudget: fields.isOutsideBudget, createdAt: editing?.createdAt ?? Date(),
            handledMonth: editing?.frequency == frequency ? (editing?.handledMonth ?? "") : "",
            frequency: frequency, weekday: weekday, monthOfYear: month, autoRecord: autoRecord,
            remindDayBefore: remindDayBefore
        )
        return RecurringPlanner.nextDueDate(for: item, now: Date(), calendar: calendar)
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
                frequency: frequency, weekday: weekday, monthOfYear: month, autoRecord: autoRecord,
                remindDayBefore: remindDayBefore
            )
        } else {
            recorder.addRecurring(
                name: name, amount: amount, categoryKey: fields.categoryKey, dayOfMonth: day,
                isOutsideBudget: fields.isOutsideBudget, now: Date(),
                frequency: frequency, weekday: weekday, monthOfYear: month, autoRecord: autoRecord,
                remindDayBefore: remindDayBefore
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
