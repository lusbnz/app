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
    @Query private var budgets: [CategoryBudget]
    @State private var text: String
    @State private var overrides: [Int: EntryOverride] = [:]
    @State private var editing: EntryRow?
    @State private var showsPaywall = false
    @State private var duplicate: PendingDuplicate?
    @State private var voice = VoiceInput()
    @State private var voiceBase = ""
    @State private var placeState = EntryPlaceState.none
    @FocusState private var isFocused: Bool
    private let startsListening: Bool

    let now: Date
    private let parser = ExpenseParser(rates: ExchangeRates.load())

    init(request: EntryRequest, now: Date) {
        self.now = now
        startsListening = request.startsListening
        _text = State(initialValue: request.text)
        let since = Calendar.current.date(byAdding: .day, value: -35, to: now) ?? now
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= since }, sort: \Expense.createdAt, order: .reverse)
    }

    private var status: BudgetStatus {
        BudgetCalculator.status(settings.budgetSetting, entries: expenses.map(\.budgetEntry), now: now, calendar: calendar)
    }

    var body: some View {
        let status = status
        let lines = parser.parse(text, rules: rules.lookup, dailyAllowance: status.allowanceToday, now: now, calendar: calendar)
        let rows = EntryRows.resolve(lines, overrides: overrides, dailyAllowance: status.allowanceToday)
        let question: String? = if case .question(let question)? = lines.first { question } else { nil }
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    remaining(status, rows: rows)
                    HStack(alignment: .top, spacing: 4) {
                        TextField("phở 45k", text: $text, axis: .vertical)
                            .focused($isFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .padding(.vertical, 14)
                            .accessibilityLabel("Khoản chi")
                        if voice.isSupported { microphoneButton }
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, voice.isSupported ? 6 : 20)
                    .background(Color.xuSurface, in: .rect(cornerRadius: 26))
                    if let message = voiceMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    EntryPlaceChip(
                        state: placeState,
                        remove: { placeState = .removed },
                        restore: { placeState = .none; Task { await resolvePlace() } }
                    )
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
        .sensoryFeedback(.success, trigger: heardAmount(rows)) { old, new in !old && new }
        .onChange(of: voice.transcript) { _, spoken in
            // Chữ nói được thay phần đang nói; chữ gõ trước đó được giữ nguyên.
            guard !spoken.isEmpty else { return }
            let heard = voiceBase + SpokenNumbers.normalize(spoken)
            // Chữ nói ra không tự viết hoa như chữ gõ.
            text = voiceBase.isEmpty ? heard.prefix(1).uppercased() + heard.dropFirst() : heard
        }
        .onDisappear { voice.cancel() }
        .task(id: coordinateKey) { await resolvePlace() }
        .onAppear {
            if startsListening, voice.isSupported {
                startListening()
            } else {
                isFocused = true
            }
            if settings.suggestionsEnabled { location.refresh() }
        }
        .confirmationDialog(
            "Ghi trùng?", isPresented: Binding { duplicate != nil } set: { if !$0 { duplicate = nil } },
            titleVisibility: .visible, presenting: duplicate
        ) { pending in
            Button("Vẫn ghi") { record(pending.items, rawText: pending.rawText, confirmedDuplicate: true) }
            Button("Không ghi", role: .cancel) {}
        } message: { pending in
            Text("“\(pending.name)” \(MoneyFormatter.short(pending.amount)) \(pending.minutesAgo < 1 ? String(localized: "vừa được ghi") : String(localized: "đã ghi cách đây \(pending.minutesAgo) phút")).")
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(item: $editing) { row in
            EntryRowEditor(row: row) { overrides[row.id] = $0 }
        }
    }

    // MARK: - Nơi ghi

    /// Đổi khi vị trí đổi (khoảng 10 m), để tra lại tên nơi.
    private var coordinateKey: String? {
        guard settings.suggestionsEnabled, let coordinate = location.freshCoordinate else { return nil }
        return String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    /// Tên nơi sẽ gắn vào khoản này: dùng lại tên đã có ở cùng chỗ (không cần mạng), không thì tìm quán gần đó
    /// khi người dùng đã bật "Tự nhận tên nơi ghi".
    private func resolvePlace() async {
        guard placeState != .removed else { return }
        guard settings.suggestionsEnabled, let coordinate = location.freshCoordinate else {
            placeState = .none
            return
        }
        let known = ExpenseRecorder(context: modelContext).namedPlaces()
        if let name = PlaceNaming.reusableName(near: coordinate, in: known) {
            placeState = .named(name)
            return
        }
        guard settings.placeLookupEnabled else {
            placeState = .none
            return
        }
        placeState = .searching
        let name = await PlaceLookup.shared.bestName(near: coordinate)
        // Trong lúc chờ mạng người dùng có thể đã bỏ nơi này.
        guard placeState == .searching else { return }
        placeState = name.map(EntryPlaceState.named) ?? .none
    }

    // MARK: - Giọng nói

    private func startListening() {
        isFocused = false
        voiceBase = text.isEmpty || text.hasSuffix(" ") ? text : text + " "
        Task { await voice.start() }
    }

    private var microphoneButton: some View {
        let isListening = voice.state == .listening
        return Button {
            if isListening { voice.stop() } else { startListening() }
        } label: {
            // Cao bằng một dòng của ô gõ (cùng padding dọc 14), nên nút nằm giữa dòng đầu
            // cả khi ô gõ xuống nhiều dòng.
            ZStack {
                Text(" ")
                    .padding(.vertical, 14)
                    .hidden()
                Image(systemName: isListening ? "stop.circle.fill" : "mic")
                    .font(.title3)
            }
            .frame(width: 44)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Dừng nói" : "Nói khoản chi")
    }

    /// Đang nói và đã nghe ra ít nhất một số tiền: rung nhẹ một lần để biết Pennyline hiểu đúng.
    private func heardAmount(_ rows: [EntryRow]) -> Bool {
        voice.state == .listening && rows.contains { $0.amount != nil }
    }

    private var voiceMessage: String? {
        switch voice.state {
        case .denied: String(localized: "Pennyline chưa được dùng micro hoặc nhận dạng giọng nói. Bạn bật lại trong Cài đặt của iPhone.")
        case .unavailable: String(localized: "Máy này chưa nhận dạng được giọng nói tiếng Việt.")
        case .idle, .listening: nil
        }
    }

    /// Con số phía trên: còn lại hôm nay, hoặc còn lại sau khi ghi các khoản đang gõ.
    private func remaining(_ status: BudgetStatus, rows: [EntryRow]) -> some View {
        let pendingRows = rows.filter { !$0.isLoan && !$0.isOutsideBudget }
        let pending = pendingRows.reduce(0) { $0 + ($1.amount ?? 0) }
        var after = status.remainingToday - pending
        var allowance = status.allowanceToday
        let limits = settings.dailyLimits(budgets)
        if !limits.isEmpty {
            // Hạn mức danh mục giữ riêng một phần tiền, nên phải tính lại với các khoản đang gõ.
            let typed = pendingRows.compactMap { row in
                row.amount.map { BudgetEntry(amount: $0, date: row.date ?? now, categoryKey: row.categoryKey) }
            }
            let shaped = BudgetCalculator.status(
                settings.budgetSetting, entries: expenses.map(\.budgetEntry) + typed,
                categoryLimits: limits, now: now, calendar: calendar
            )
            after = shaped.remainingToday
            allowance = shaped.allowanceToday
        }
        let fraction = allowance > 0 ? Double(max(after, 0)) / Double(allowance) : 0
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

    /// Khoản vừa ghi giống hệt khoản sắp ghi (trong 5 phút), nếu có.
    private func firstDuplicate(of items: [RecordItem]) -> PendingDuplicate? {
        let current = Date()
        let recent = expenses.map { RecentEntry(name: $0.name, amount: $0.amount, date: $0.date, createdAt: $0.createdAt) }
        for case .expense(let draft) in items {
            if let match = DuplicateDetector.match(
                name: draft.name, amount: draft.amount, date: draft.date ?? current, among: recent, now: current, calendar: calendar
            ) {
                let minutes = Int(current.timeIntervalSince(match.createdAt) / 60)
                return PendingDuplicate(items: items, name: draft.displayName, amount: draft.amount, minutesAgo: minutes)
            }
        }
        return nil
    }

    private func record(_ items: [RecordItem], rawText: String, confirmedDuplicate: Bool = false) {
        // Bản miễn phí: lần lưu thứ 6 trong ngày mở Pennyline Pro.
        guard SaveGate.canSave(now: Date(), calendar: calendar) else {
            showsPaywall = true
            return
        }
        if !confirmedDuplicate, let pending = firstDuplicate(of: items) {
            duplicate = pending.withRawText(rawText)
            return
        }
        var info = RecordContext(rawText: rawText, date: Date())
        if settings.suggestionsEnabled, placeState.savesLocation, let coordinate = location.freshCoordinate {
            info.latitude = coordinate.latitude
            info.longitude = coordinate.longitude
            info.placeName = placeState.name
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

/// Lần ghi đang chờ người dùng xác nhận vì giống khoản vừa ghi.
struct PendingDuplicate: Identifiable {
    let id = UUID()
    var items: [RecordItem]
    var name: String
    var amount: Int
    var minutesAgo: Int
    var rawText = ""

    func withRawText(_ text: String) -> PendingDuplicate {
        var copy = self
        copy.rawText = text
        return copy
    }
}
