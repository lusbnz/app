import SwiftData
import SwiftUI

/// Ô gõ: gõ một dòng, xem trước từng khoản đã tách, rồi Ghi.
struct EntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @Query private var expenses: [Expense]
    @Query private var rules: [CategoryRule]
    @State private var text: String
    @State private var overrides: [Int: EntryOverride] = [:]
    @State private var editing: EntryRow?
    @FocusState private var isFocused: Bool

    let now: Date
    private let parser = ExpenseParser()

    init(request: EntryRequest, now: Date) {
        self.now = now
        _text = State(initialValue: request.text)
        let since = Calendar.current.date(byAdding: .day, value: -35, to: now) ?? now
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= since }, sort: \Expense.createdAt, order: .reverse)
    }

    private var status: BudgetStatus {
        BudgetCalculator.status(
            monthlyBudget: settings.monthlyBudget, entries: expenses.map(\.budgetEntry), now: now, calendar: calendar
        )
    }

    var body: some View {
        let status = status
        let lines = parser.parse(text, rules: rules.lookup, dailyAllowance: status.allowanceToday)
        let rows = EntryRows.resolve(lines, overrides: overrides, dailyAllowance: status.allowanceToday)
        let question: String? = if case .question(let question)? = lines.first { question } else { nil }
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    remaining(status, rows: rows)
                    TextField("phở 45k", text: $text, axis: .vertical)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.xuSurface, in: .rect(cornerRadius: 26))
                        .accessibilityLabel("Khoản chi")
                    if isEmpty {
                        Text("Hỏi cũng được: tháng này cf hết bao nhiêu?")
                            .font(.footnote)
                            .foregroundStyle(Color.xuTextSecondary)
                        if settings.suggestionsEnabled {
                            suggestions
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                Button { if !row.isLoan { editing = row } } label: { EntryRowView(row: row) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.never)
            .xuScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let question {
                        Button("Hỏi") {
                            dismiss()
                            appState.ask(question)
                        }
                    } else {
                        Button("Ghi") { save(rows) }
                            .disabled(rows.isEmpty || rows.contains { $0.amount == nil })
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
            if settings.suggestionsEnabled { location.refresh() }
        }
        .sheet(item: $editing) { row in
            EntryRowEditor(row: row) { overrides[row.id] = $0 }
        }
    }

    /// Con số phía trên: còn lại hôm nay, hoặc còn lại sau khi ghi các khoản đang gõ.
    private func remaining(_ status: BudgetStatus, rows: [EntryRow]) -> some View {
        let pending = rows.filter { !$0.isLoan && !$0.isOutsideBudget }.reduce(0) { $0 + ($1.amount ?? 0) }
        let after = status.remainingToday - pending
        let fraction = status.allowanceToday > 0 ? Double(max(after, 0)) / Double(status.allowanceToday) : 0
        return VStack(alignment: .leading, spacing: 2) {
            HighlightedNumber(text: MoneyFormatter.short(after), fraction: fraction, size: 44)
            Text(pending > 0 ? "còn lại sau khi ghi" : "còn được tiêu hôm nay")
                .font(.footnote)
                .foregroundStyle(Color.xuTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pending > 0
            ? "Còn lại sau khi ghi \(MoneyFormatter.spoken(after))"
            : "Còn được tiêu hôm nay \(MoneyFormatter.spoken(after))")
    }

    // MARK: - Gợi ý

    /// Tối đa ba gợi ý: nơi quen đang ở gần, rồi những khoản hay ghi vào buổi này.
    @ViewBuilder
    private var suggestions: some View {
        let current = Date()
        let records = expenses.map(\.suggestionRecord)
        let nearby = location.freshCoordinate.flatMap {
            PlaceSuggester.suggestion(near: $0, records: records, now: current, calendar: calendar)
        }
        let timed = TimeSuggester.suggestions(records: records, now: current, calendar: calendar)
            .filter { $0.id != nearby?.suggestion.id }
            .prefix(nearby == nil ? 3 : 2)
        VStack(alignment: .leading, spacing: 0) {
            if let nearby {
                suggestionLabel(String(localized: "Bạn đang gần \(nearby.place.label)"))
                suggestionRow(nearby.suggestion)
            }
            if !timed.isEmpty {
                suggestionLabel(TimeSuggester.label(now: current, calendar: calendar))
                ForEach(Array(timed)) { suggestionRow($0) }
            }
        }
    }

    private func suggestionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.xuTextSecondary)
            .padding(.top, 14)
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        Button {
            let draft = ExpenseDraft(name: suggestion.name, amount: suggestion.amount, categoryKey: suggestion.categoryKey)
            record([.expense(draft)], rawText: suggestion.name)
        } label: {
            HStack {
                Text(suggestion.name)
                Text(MoneyFormatter.short(suggestion.amount))
                    .foregroundStyle(Color.xuTextSecondary)
                    .money(suggestion.amount)
                Spacer()
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.xuSurface, in: .circle)
            }
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ghi ngay")
    }

    // MARK: - Lưu

    private func save(_ rows: [EntryRow]) {
        let items = rows.compactMap(\.recordItem)
        guard !items.isEmpty, items.count == rows.count else { return }
        record(items, rawText: text)
    }

    private func record(_ items: [RecordItem], rawText: String) {
        var info = RecordContext(rawText: rawText, date: Date())
        if settings.suggestionsEnabled, let coordinate = location.freshCoordinate {
            info.latitude = coordinate.latitude
            info.longitude = coordinate.longitude
        }
        let batch = ExpenseRecorder(context: modelContext).record(items, in: info)
        appState.didSave(batch)
        dismiss()
    }
}

/// Sửa nhanh một dòng xem trước: số tiền, danh mục, ngoài ngân sách.
struct EntryRowEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fields: ExpenseFields

    let row: EntryRow
    let apply: (EntryOverride) -> Void

    init(row: EntryRow, apply: @escaping (EntryOverride) -> Void) {
        self.row = row
        self.apply = apply
        _fields = State(initialValue: ExpenseFields(
            name: row.name, amountText: ExpenseFields.amountText(for: row.amount),
            categoryKey: row.categoryKey, isOutsideBudget: row.isOutsideBudget
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ExpenseFieldsEditor(fields: $fields, showsName: false, showsDate: false)
                    .padding(.horizontal, 24)
            }
            .xuScreen()
            .navigationTitle(row.name.isEmpty ? String(localized: "khoản chi") : row.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        apply(EntryOverride(
                            name: row.name, amount: fields.amount, categoryKey: fields.categoryKey,
                            isOutsideBudget: fields.isOutsideBudget == row.isOutsideBudget && fields.amount != row.amount
                                ? nil : fields.isOutsideBudget
                        ))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .fontDesign(.rounded)
    }
}

#Preview("Trống") {
    EntryView(request: EntryRequest(), now: Date()).xuPreview()
}

#Preview("Đang gõ") {
    EntryView(request: EntryRequest(text: "cơm tấm 55, đổ xăng 80k, tai nghe 1tr2"), now: Date()).xuPreview()
}
