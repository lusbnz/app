import SwiftData
import SwiftUI

/// Màn hình gốc: hôm nay còn được tiêu bao nhiêu.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var expenses: [Expense]
    @State private var selected: Expense?

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

    var body: some View {
        @Bindable var appState = appState
        let status = status
        List {
            Group {
                header(status)
                ForEach(todays) { expense in
                    Button { selected = expense } label: { ExpenseRow(expense: expense) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Xóa", role: .destructive) {
                                ExpenseRecorder(context: modelContext).delete(expense)
                            }
                        }
                }
                previousDays
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.default, value: todays.map(\.id))
        .xuScreen()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationDestination(isPresented: $appState.showsMonth) {
            MonthView(now: now)
        }
        .sheet(item: $selected) { expense in
            ExpenseDetailView(expense: expense)
        }
        .sheet(isPresented: $appState.showsSettings) {
            SettingsView()
        }
    }

    // MARK: - Phần đầu

    private func header(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(VietnameseDate.dayTitle(now, calendar: calendar))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.xuTextSecondary)
                Spacer()
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

    // MARK: - Ba ngày trước

    private var previousDays: some View {
        let totals = BudgetCalculator.previousDayTotals(
            entries: expenses.map(\.budgetEntry), days: 3, now: now, calendar: calendar
        )
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(totals, id: \.day) { item in
                Text("\(VietnameseDate.relativeDay(item.day, now: now, calendar: calendar)) \(MoneyFormatter.short(item.total))")
                    .monospacedDigit()
                    .accessibilityLabel("\(VietnameseDate.relativeDay(item.day, now: now, calendar: calendar)) \(MoneyFormatter.spoken(item.total))")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.xuTextSecondary)
        .padding(.top, 20)
        .padding(.bottom, 12)
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
