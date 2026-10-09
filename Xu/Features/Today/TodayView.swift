import SwiftData
import SwiftUI

/// Màn hình gốc: hôm nay còn được tiêu bao nhiêu.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var expenses: [Expense]
    @Query private var customCategories: [CustomCategory]
    @Query private var recurring: [RecurringExpense]
    @State private var selected: Expense?
    @State private var reapply: ReapplyOffer?
    @State private var isScrolling = false
    @State private var hapticDay: Date?

    let now: Date

    init(now: Date) {
        self.now = now
        // Đủ cho cả tháng hiện tại và ba ngày trước.
        let since = Calendar.current.date(byAdding: .day, value: -35, to: now) ?? now
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= since }, sort: \Expense.createdAt, order: .reverse)
    }

    private var status: BudgetStatus {
        BudgetCalculator.status(
            monthlyBudget: settings.monthlyBudget, entries: expenses.map(\.budgetEntry), now: now, calendar: calendar
        )
    }

    private var todays: [Expense] {
        expenses.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Khoản định kỳ đã đến hạn tháng này mà chưa ghi hay bỏ qua.
    private var dueRecurring: [RecurringExpense] {
        recurring
            .filter { RecurringPlanner.isDue($0.item, now: now, calendar: calendar) }
            .sorted { ($0.dayOfMonth, $0.name) < ($1.dayOfMonth, $1.name) }
    }

    var body: some View {
        @Bindable var appState = appState
        let status = status
        List {
            Group {
                header(status)
                ForEach(dueRecurring) { item in
                    DueRecurringRow(item: item) { recordRecurring(item) } skip: { skipRecurring(item) }
                }
                if !todays.isEmpty { todayHeader }
                ForEach(todays) { expenseRow($0) }
                pastDays
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.default, value: todays.map(\.id))
        .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
        .sensoryFeedback(.selection, trigger: hapticDay)
        .xuScreen()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationDestination(isPresented: $appState.showsMonth) {
            MonthView(now: now)
        }
        .sheet(item: $selected) { expense in
            ExpenseDetailView(expense: expense)
        }
        .reapplyDialog($reapply)
        .sheet(isPresented: $appState.showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showsSearch) {
            SearchView(now: now)
        }
    }

    /// Ghi lại một khoản y như cũ. Bản miễn phí vẫn bị giới hạn số lần ghi mỗi ngày.
    private func repeatExpense(_ expense: Expense) {
        guard SaveGate.canSave(now: Date(), calendar: calendar) else {
            appState.showsPaywall = true
            return
        }
        let batch = ExpenseRecorder(context: modelContext).repeatExpense(expense, now: Date())
        appState.didSave(batch)
    }

    private func recordRecurring(_ item: RecurringExpense) {
        guard SaveGate.canSave(now: Date(), calendar: calendar) else {
            appState.showsPaywall = true
            return
        }
        withAnimation {
            if let batch = ExpenseRecorder(context: modelContext).recordRecurring(item, now: Date(), calendar: calendar) {
                appState.didSave(batch)
            }
        }
    }

    private func skipRecurring(_ item: RecurringExpense) {
        withAnimation { ExpenseRecorder(context: modelContext).skipRecurring(item, now: Date(), calendar: calendar) }
    }

    // MARK: - Phần đầu

    private func header(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(VietnameseDate.dayTitle(now, calendar: calendar))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.xuTextSecondary)
                Spacer()
                Button { appState.showsSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tìm khoản chi")
                Button { appState.showsSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tùy chỉnh")
            }
            Button { appState.showsMonth = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HighlightedNumber(
                        text: MoneyFormatter.short(status.remainingToday),
                        fraction: status.todayFraction
                    )
                    Text(subtitle(status))
                        .font(.subheadline)
                        .foregroundStyle(Color.xuTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(status))
            .accessibilityHint("Mở màn hình Tháng")
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func subtitle(_ status: BudgetStatus) -> String {
        if status.remainingToday < 0 {
            if let tomorrow = status.allowanceTomorrow, tomorrow > 0 {
                return String(localized: "vượt hôm nay · mai vẫn còn \(MoneyFormatter.short(tomorrow))")
            }
            return String(localized: "vượt hôm nay")
        }
        return String(localized: "còn được tiêu hôm nay · đã tiêu \(MoneyFormatter.short(status.spentToday))")
    }

    private func accessibilitySummary(_ status: BudgetStatus) -> String {
        if status.remainingToday < 0 {
            let over = MoneyFormatter.spoken(-status.remainingToday)
            if let tomorrow = status.allowanceTomorrow, tomorrow > 0 {
                return String(localized: "Hôm nay vượt \(over), mai vẫn còn \(MoneyFormatter.spoken(tomorrow))")
            }
            return String(localized: "Hôm nay vượt \(over)")
        }
        return String(localized: "Còn được tiêu hôm nay \(MoneyFormatter.spoken(status.remainingToday)), đã tiêu \(MoneyFormatter.spoken(status.spentToday))")
    }

    /// Một dòng khoản chi, kèm các nút vuốt nhanh. Dùng cho hôm nay và các ngày trước.
    private func expenseRow(_ expense: Expense) -> some View {
        Button { selected = expense } label: { ExpenseRow(expense: expense, categoryTitle: CategoryCatalog(custom: customCategories).info(for: expense.categoryKey).title) }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading) {
                Button("Ghi lại", systemImage: "plus.circle") { repeatExpense(expense) }
                    .tint(Color.xuToggle)
                Button(
                    expense.isOutsideBudget ? "Tính vào ngân sách" : "Ngoài ngân sách",
                    systemImage: expense.isOutsideBudget ? "arrow.uturn.backward" : "tray.and.arrow.up"
                ) {
                    withAnimation { ExpenseRecorder(context: modelContext).toggleOutsideBudget(expense) }
                }
                .tint(Color.gray)
            }
            .swipeActions(edge: .trailing) {
                Button("Xóa", systemImage: "trash", role: .destructive) {
                    ExpenseRecorder(context: modelContext).delete(expense)
                }
                Menu {
                    ForEach(CategoryCatalog(custom: customCategories).all) { category in
                        Button(category.title) {
                            let recorder = ExpenseRecorder(context: modelContext)
                            recorder.setCategory(of: expense, to: category.key)
                            reapply = recorder.reapplyOffer(keyword: expense.name, categoryKey: category.key)
                        }
                    }
                } label: {
                    Label("Danh mục", systemImage: "tag")
                }
                .tint(Color.gray)
            }
    }

    // MARK: - Các ngày trước

    /// Các ngày trước hôm nay có khoản chi, mới nhất trước. Cuộn xuống là xem tiếp, không cần bấm.
    private var pastGroups: [(day: Date, expenses: [Expense])] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: expenses.filter { $0.date < today }) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (day: $0.key, expenses: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    @ViewBuilder
    private var pastDays: some View {
        ForEach(pastGroups, id: \.day) { group in
            let total = group.expenses.filter { !$0.isOutsideBudget }.reduce(0) { $0 + $1.amount }
            dayHeader(group.day, total: total)
            ForEach(group.expenses) { expenseRow($0) }
        }
    }

    /// Tiêu đề và tổng của hôm nay, cùng kiểu với các ngày trước. Không tính khoản ngoài ngân sách.
    private var todayHeader: some View {
        let total = todays.filter { !$0.isOutsideBudget }.reduce(0) { $0 + $1.amount }
        return groupTitle(VietnameseDate.relativeDay(now, now: now, calendar: calendar), total: total)
            .padding(.top, 8)
    }

    private func groupTitle(_ title: String, total: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(MoneyFormatter.short(total)).money(total)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.xuTextSecondary)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func dayHeader(_ day: Date, total: Int) -> some View {
        groupTitle(VietnameseDate.relativeDay(day, now: now, calendar: calendar), total: total)
            .padding(.top, 24)
        // Rung nhẹ mỗi khi một ngày mới trượt vào màn hình, chỉ khi người dùng đang cuộn.
        .onScrollVisibilityChange(threshold: 0.9) { visible in
            if visible, isScrolling { hapticDay = day }
        }
    }

    // MARK: - Đáy màn hình

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let batch = appState.undoable {
                UndoBar(batch: batch) {
                    ExpenseRecorder(context: modelContext).undo(batch)
                    appState.undoable = nil
                } dismiss: {
                    appState.undoable = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Button { appState.openEntry() } label: {
                    Text("phở 45k")
                        .foregroundStyle(Color.xuTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 20)
                        .background(Color.xuSurface, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ghi khoản chi")
                Button {
                    appState.receiptImage = nil
                    appState.showsReceipt = true
                } label: {
                    Image(systemName: "camera")
                        .font(.title3)
                        .frame(width: 50, height: 50)
                        .background(Color.xuSurface, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chụp hóa đơn")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.xuBackground)
        .animation(.snappy, value: appState.undoable)
    }
}

#Preview {
    NavigationStack {
        TodayView(now: Date())
    }
    .xuPreview()
}

#Preview("Vượt hạn mức") {
    NavigationStack {
        TodayView(now: Date())
    }
    .xuPreview(budget: 3_000_000)
}
