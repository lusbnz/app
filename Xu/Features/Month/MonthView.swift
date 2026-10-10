import SwiftData
import SwiftUI

/// Màn hình Tháng: còn lại của kỳ ngân sách (tháng hoặc tuần), dự báo, hạn mức danh mục, các danh mục, chi ở đâu nhiều nhất,
/// so với kỳ trước, mục tiêu tiết kiệm, các khoản không tính vào ngân sách.
struct MonthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query(sort: \Loan.date, order: .reverse) private var allLoans: [Loan]
    @Query private var customCategories: [CustomCategory]
    @Query private var budgets: [CategoryBudget]
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var deposits: [SavingsDeposit]
    @State private var selected: Expense?
    @State private var comparePeriod = ComparisonPeriod.month
    @State private var showsMap = false
    @State private var mapFocus: String?
    @State private var showsGoals = false
    @State private var openedGoal: SavingsGoal?

    let now: Date

    /// Các khoản của tháng này. Lọc trong bộ nhớ: ở màn hình nằm trong navigationDestination,
    /// @Query có `filter` làm SwiftUI truy vấn và dựng lại liên tục (treo máy trên iOS 26).
    private var expenses: [Expense] {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return allExpenses.filter { $0.date >= start }
    }

    private func makeSnapshot(_ expenses: [Expense]) -> SpendingSnapshot {
        SpendingSnapshot.make(
            expenses: expenses, budget: settings.budgetSetting, customCategories: customCategories, now: now, calendar: calendar
        )
    }

    var body: some View {
        let expenses = expenses
        let status = BudgetCalculator.status(
            settings.budgetSetting, entries: allExpenses.map(\.budgetEntry), now: now, calendar: calendar
        )
        let snapshot = makeSnapshot(expenses)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(status)
                limits(expenses)
                categories(snapshot)
                topPlaces(expenses)
                comparison()
                savings(status)
                outside(expenses)
                AskSection(snapshot: snapshot)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .xuScreen()
        .navigationTitle(VietnameseDate.monthTitle(now, calendar: calendar))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { expense in
            ExpenseDetailView(expense: expense)
        }
        .navigationDestination(isPresented: $showsMap) {
            PlacesMapView(now: now, initialSelection: mapFocus)
        }
        .navigationDestination(isPresented: $showsGoals) {
            SavingsGoalsView()
        }
        .navigationDestination(item: $openedGoal) { goal in
            SavingsGoalDetailView(goal: goal)
        }
        #if DEBUG
        .task {
            // Cờ chạy thử `-open map|goals|goal`: mở thẳng một màn con.
            guard let destination = appState.debugMonthDestination else { return }
            appState.debugMonthDestination = nil
            try? await Task.sleep(for: .milliseconds(600))
            switch destination {
            case "map": showsMap = true
            case "goals": showsGoals = true
            case "goal": openedGoal = goals.first
            default: break
            }
        }
        #endif
    }

    // MARK: - Phần đầu

    private func header(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.period == .week {
                Text("Ngân sách tuần")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.xuTextSecondary)
            }
            HighlightedNumber(text: MoneyFormatter.short(status.remainingThisPeriod), fraction: status.periodFraction)
            Text("đã tiêu \(MoneyFormatter.short(status.spentThisPeriod)) trên \(MoneyFormatter.short(status.budget))")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            Text(forecast(status))
                .font(.body)
                .padding(.top, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerSpoken(status))
    }

    private func headerSpoken(_ status: BudgetStatus) -> String {
        let left = MoneyFormatter.spoken(status.remainingThisPeriod)
        let spent = MoneyFormatter.spoken(status.spentThisPeriod)
        let budget = MoneyFormatter.spoken(status.budget)
        return status.period == .week
            ? String(localized: "Tuần này còn \(left), đã tiêu \(spent) trên \(budget). \(forecast(status))")
            : String(localized: "Tháng này còn \(left), đã tiêu \(spent) trên \(budget). \(forecast(status))")
    }

    private func forecast(_ status: BudgetStatus) -> String {
        let isWeek = status.period == .week
        guard status.spentThisPeriod > 0 else {
            return isWeek ? String(localized: "Tuần này chưa tiêu gì.") : String(localized: "Tháng này chưa tiêu gì.")
        }
        let forecast = BudgetCalculator.forecast(for: status)
        let pace = MoneyFormatter.short(forecast.pacePerDay)
        let leftover = MoneyFormatter.short(abs(forecast.projectedLeftover))
        switch (isWeek, forecast.projectedLeftover >= 0) {
        case (false, true): return String(localized: "Giữ nhịp \(pace) mỗi ngày, cuối tháng dư khoảng \(leftover).")
        case (false, false): return String(localized: "Giữ nhịp \(pace) mỗi ngày, cuối tháng vượt khoảng \(leftover).")
        case (true, true): return String(localized: "Giữ nhịp \(pace) mỗi ngày, cuối tuần dư khoảng \(leftover).")
        case (true, false): return String(localized: "Giữ nhịp \(pace) mỗi ngày, cuối tuần vượt khoảng \(leftover).")
        }
    }

    // MARK: - Hạn mức danh mục

    @ViewBuilder
    private func limits(_ expenses: [Expense]) -> some View {
        let statuses = CategoryBudgetCalculator.statuses(
            limits: budgets.lookup, records: expenses.map(\.record), now: now, calendar: calendar
        )
        if !statuses.isEmpty {
            let catalog = CategoryCatalog(custom: customCategories)
            VStack(alignment: .leading, spacing: 14) {
                Text("Hạn mức danh mục")
                    .font(.subheadline.weight(.semibold))
                ForEach(statuses) { status in
                    let category = catalog.info(for: status.key)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            CategoryLabel(category: category)
                            Spacer()
                            Text("\(MoneyFormatter.short(status.spent)) / \(MoneyFormatter.short(status.limit))")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(status.level == .over ? Color.red : category.color)
                                .frame(width: max(6, proxy.size.width * status.fraction))
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                        if let note = limitNote(status) {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(status.level == .over ? Color.red : Color.xuTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func limitNote(_ status: CategoryLimitStatus) -> String? {
        switch status.level {
        case .ok: nil
        case .near: String(localized: "gần chạm hạn mức, còn \(MoneyFormatter.short(status.remaining))")
        case .over: String(localized: "vượt hạn mức \(MoneyFormatter.short(-status.remaining))")
        }
    }

    // MARK: - Danh mục

    @ViewBuilder
    private func categories(_ snapshot: SpendingSnapshot) -> some View {
        if let largest = snapshot.byCategory.first?.total, largest > 0 {
            VStack(spacing: 14) {
                ForEach(snapshot.byCategory) { group in
                    let category = CategoryCatalog(custom: customCategories).info(for: group.key)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            CategoryLabel(category: category)
                            Spacer()
                            Text(MoneyFormatter.short(group.total))
                                .fontWeight(.medium)
                                .money(group.total)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(category.color)
                                .frame(width: max(6, proxy.size.width * CGFloat(group.total) / CGFloat(largest)))
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Chi ở đâu nhiều nhất

    @ViewBuilder
    private func topPlaces(_ expenses: [Expense]) -> some View {
        let spends = PlaceSpending.totals(expenses.compactMap { expense in
            guard !expense.isOutsideBudget, let latitude = expense.latitude, let longitude = expense.longitude else { return nil }
            return PlaceRecord(
                coordinate: Coordinate(latitude: latitude, longitude: longitude), name: expense.placeName,
                amount: expense.amount, date: expense.date, categoryKey: expense.categoryKey
            )
        })
        if let largest = spends.first?.total, largest > 0 {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Chi ở đâu nhiều nhất")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Bản đồ") {
                        mapFocus = nil
                        showsMap = true
                    }
                    .font(.subheadline)
                }
                ForEach(spends.prefix(5)) { spend in
                    Button {
                        mapFocus = spend.id
                        showsMap = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(spend.name ?? String(localized: "Chưa đặt tên"), systemImage: "mappin.and.ellipse")
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(MoneyFormatter.short(spend.total))
                                    .fontWeight(.medium)
                                    .money(spend.total)
                            }
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Color.xuHighlight)
                                    .frame(width: max(6, proxy.size.width * CGFloat(spend.total) / CGFloat(largest)))
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                            Text("\(spend.count) lần")
                                .font(.caption)
                                .foregroundStyle(Color.xuTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Mục tiêu tiết kiệm

    private func savings(_ status: BudgetStatus) -> some View {
        let saved = Dictionary(grouping: deposits, by: \.goalID).mapValues { max(0, $0.reduce(0) { $0 + $1.amount }) }
        func isDone(_ goal: SavingsGoal) -> Bool {
            goal.targetAmount > 0 && (saved[goal.id] ?? 0) >= goal.targetAmount
        }
        // Mục tiêu chưa đủ đứng trước.
        let shown = goals.sorted { (isDone($0) ? 1 : 0, $0.createdAt) < (isDone($1) ? 1 : 0, $1.createdAt) }
        let leftover = status.spentThisPeriod > 0 ? BudgetCalculator.forecast(for: status).projectedLeftover : 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Mục tiêu tiết kiệm")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(goals.isEmpty ? "Đặt mục tiêu" : "Xem tất cả") { showsGoals = true }
                    .font(.subheadline)
            }
            if goals.isEmpty {
                Text("Chưa có mục tiêu nào. Đặt một mục tiêu để để dành dần, ví dụ du lịch hay mua xe.")
                    .font(.footnote)
                    .foregroundStyle(Color.xuTextSecondary)
            } else {
                ForEach(shown.prefix(3)) { goal in
                    Button { openedGoal = goal } label: {
                        SavingsGoalRow(goal: goal, saved: saved[goal.id] ?? 0, now: now)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if leftover > 0 {
                    Text(status.period == .week
                         ? String(localized: "Giữ nhịp này thì cuối tuần dư khoảng \(MoneyFormatter.short(leftover)). Chạm một mục tiêu để gửi phần dư vào.")
                         : String(localized: "Giữ nhịp này thì cuối tháng dư khoảng \(MoneyFormatter.short(leftover)). Chạm một mục tiêu để gửi phần dư vào."))
                        .font(.footnote)
                        .foregroundStyle(Color.xuTextSecondary)
                }
            }
        }
    }

    // MARK: - So với kỳ trước

    @ViewBuilder
    private func comparison() -> some View {
        let result = PeriodComparison.make(records: allExpenses.map(\.record), period: comparePeriod, now: now, calendar: calendar)
        if result.hasData {
            let catalog = CategoryCatalog(custom: customCategories)
            VStack(alignment: .leading, spacing: 14) {
                Text("So với kỳ trước")
                    .font(.subheadline.weight(.semibold))
                Picker("Kỳ so sánh", selection: $comparePeriod) {
                    Text("Tháng trước").tag(ComparisonPeriod.month)
                    Text("Tuần trước").tag(ComparisonPeriod.week)
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 2) {
                    Text(changeText(result.delta, percent: result.previousTotal > 0 ? PeriodComparison.percent(result.delta, of: result.previousTotal) : nil))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(result.delta > 0 ? Color.red : Color.xuTextPrimary)
                    Text(comparePeriod == .month
                         ? "\(MoneyFormatter.short(result.currentTotal)) so với \(MoneyFormatter.short(result.previousTotal)) cùng ngày tháng trước"
                         : "\(MoneyFormatter.short(result.currentTotal)) so với \(MoneyFormatter.short(result.previousTotal)) cùng ngày tuần trước")
                        .font(.footnote)
                        .foregroundStyle(Color.xuTextSecondary)
                }
                ForEach(result.changes.prefix(6)) { change in
                    HStack {
                        CategoryLabel(category: catalog.info(for: change.key))
                        Spacer()
                        Text(changeText(change.delta, percent: change.percent))
                            .font(.subheadline)
                            .foregroundStyle(change.delta > 0 ? Color.red : Color.xuTextSecondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func changeText(_ delta: Int, percent: Int?) -> String {
        guard delta != 0 else { return String(localized: "bằng kỳ trước") }
        let amount = MoneyFormatter.short(abs(delta))
        let suffix = percent.map { " (\(abs($0))%)" } ?? ""
        return delta > 0 ? String(localized: "tăng \(amount)\(suffix)") : String(localized: "giảm \(amount)\(suffix)")
    }

    // MARK: - Không tính vào ngân sách

    @ViewBuilder
    private func outside(_ expenses: [Expense]) -> some View {
        let outsideExpenses = expenses.filter(\.isOutsideBudget)
        let loans = allLoans.filter { !$0.isRepaid }
        if !outsideExpenses.isEmpty || !loans.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Không tính vào ngân sách")
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(outsideExpenses) { expense in
                    Button { selected = expense } label: {
                        HStack {
                            Text(expense.displayName)
                            Spacer()
                            Text(MoneyFormatter.short(expense.amount)).money(expense.amount)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(loans) { loan in
                    HStack {
                        Text("ứng cho \(loan.person) · chưa trả \(MoneyFormatter.short(loan.amount))")
                            .accessibilityLabel("ứng cho \(loan.person), chưa trả \(MoneyFormatter.spoken(loan.amount))")
                        Spacer()
                        Button("Đã trả") {
                            withAnimation {
                                loan.isRepaid = true
                                ExpenseRecorder(context: modelContext).commit()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(minHeight: 52)
                }
            }
            .foregroundStyle(Color.xuTextSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        MonthView(now: Date())
    }
    .xuPreview()
}
