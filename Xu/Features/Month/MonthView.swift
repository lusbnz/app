import SwiftData
import SwiftUI

/// Màn hình Tháng: còn lại của tháng, dự báo, hạn mức danh mục, các danh mục, các khoản không tính vào ngân sách.
struct MonthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query(sort: \Loan.date, order: .reverse) private var allLoans: [Loan]
    @Query private var customCategories: [CustomCategory]
    @Query private var budgets: [CategoryBudget]
    @State private var selected: Expense?

    let now: Date

    /// Các khoản của tháng này. Lọc trong bộ nhớ: ở màn hình nằm trong navigationDestination,
    /// @Query có `filter` làm SwiftUI truy vấn và dựng lại liên tục (treo máy trên iOS 26).
    private var expenses: [Expense] {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return allExpenses.filter { $0.date >= start }
    }

    private func makeSnapshot(_ expenses: [Expense]) -> SpendingSnapshot {
        var snapshot = SpendingSnapshot.make(
            records: expenses.map(\.record), monthlyBudget: settings.monthlyBudget, now: now, calendar: calendar
        )
        snapshot.categoryNames = CategoryCatalog(custom: customCategories).titles
        return snapshot
    }

    var body: some View {
        let expenses = expenses
        let status = BudgetCalculator.status(
            monthlyBudget: settings.monthlyBudget, entries: expenses.map(\.budgetEntry), now: now, calendar: calendar
        )
        let snapshot = makeSnapshot(expenses)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(status)
                limits(expenses)
                categories(snapshot)
                outside(expenses)
                AskSection(snapshot: snapshot)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .xuScreen()
        .navigationTitle("Tháng \(calendar.component(.month, from: now))")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { expense in
            ExpenseDetailView(expense: expense)
        }
    }

    // MARK: - Phần đầu

    private func header(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HighlightedNumber(text: MoneyFormatter.short(status.remainingThisMonth), fraction: status.monthFraction)
            Text("đã tiêu \(MoneyFormatter.short(status.spentThisMonth)) trên \(MoneyFormatter.short(status.monthlyBudget))")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            Text(forecast(status))
                .font(.body)
                .padding(.top, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tháng này còn \(MoneyFormatter.spoken(status.remainingThisMonth)), đã tiêu \(MoneyFormatter.spoken(status.spentThisMonth)) trên \(MoneyFormatter.spoken(status.monthlyBudget)). \(forecast(status))")
    }

    private func forecast(_ status: BudgetStatus) -> String {
        guard status.spentThisMonth > 0 else { return String(localized: "Tháng này chưa tiêu gì.") }
        let forecast = BudgetCalculator.forecast(for: status, now: now, calendar: calendar)
        let pace = MoneyFormatter.short(forecast.pacePerDay)
        if forecast.projectedLeftover >= 0 {
            return String(localized: "Giữ nhịp \(pace) mỗi ngày, cuối tháng dư khoảng \(MoneyFormatter.short(forecast.projectedLeftover)).")
        }
        return String(localized: "Giữ nhịp \(pace) mỗi ngày, cuối tháng vượt khoảng \(MoneyFormatter.short(-forecast.projectedLeftover)).")
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
