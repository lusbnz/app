import SwiftData
import SwiftUI

/// Chi tiết một tuần (mở từ tiêu đề tuần ở màn Hôm nay): tổng và so với tuần trước, từng ngày, từng danh mục, chi ở đâu.
struct WeekDetailView: View {
    private struct SearchRequest: Identifiable {
        let id = UUID()
        var filter: ExpenseFilter
    }

    @Environment(\.calendar) private var calendar
    /// Không lọc trong `@Query`: màn hình nằm trong `navigationDestination` sẽ truy vấn lại liên tục (xem `MonthView`).
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var customCategories: [CustomCategory]
    @State private var searchRequest: SearchRequest?

    let weekStart: Date
    let now: Date

    var body: some View {
        let records = allExpenses.map(\.record)
        let summary = WeekSummaries.make(records: records, now: now, calendar: calendar)[weekStart]
        let reference = WeekDays.comparisonReference(weekStart: weekStart, now: now, calendar: calendar)
        let comparison = PeriodComparison.make(records: records, period: .week, now: reference, calendar: calendar)
        let days = WeekDays.make(records: records.filter { weekInterval.contains($0.date) }, weekStart: weekStart, now: now, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(summary: summary, comparison: comparison)
                dayBars(days)
                categories(comparison)
                places()
                Button("Xem các khoản trong tuần") {
                    searchRequest = SearchRequest(filter: ExpenseFilter(from: weekStart, to: lastDay))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .xuScreen()
        .navigationTitle(VietnameseDate.weekTitle(start: weekStart, now: now, calendar: calendar))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $searchRequest) { request in
            SearchView(now: now, initialFilter: request.filter)
        }
    }

    private var weekInterval: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: weekStart) ?? DateInterval(start: weekStart, duration: 7 * 86_400)
    }

    private var lastDay: Date {
        calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekStart
    }

    // MARK: - Phần đầu

    private func header(summary: WeekSummary?, comparison: PeriodComparison) -> some View {
        let total = summary?.total ?? comparison.currentTotal
        let larger = max(total, comparison.previousTotal, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HighlightedNumber(text: MoneyFormatter.short(total), fraction: Double(total) / Double(larger))
            Text("đã tiêu trong tuần")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            if let summary, let text = WeekText.comparison(summary) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(summary.delta > 0 ? Color.red : Color.xuTextPrimary)
                    .padding(.top, 12)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Từng ngày

    private func dayBars(_ days: [WeekDay]) -> some View {
        let largest = max(days.map(\.total).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Từng ngày")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Text(day.total > 0 ? MoneyFormatter.short(day.total) : " ")
                            .font(.caption2)
                            .foregroundStyle(Color.xuTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(day.isToday ? Color.xuHighlight : Color.xuButton)
                            .frame(height: day.isFuture ? 4 : max(6, 96 * CGFloat(day.total) / CGFloat(largest)))
                            .opacity(day.isFuture ? 0.35 : 1)
                        Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day.day) - 1])
                            .font(.caption2.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? Color.xuTextPrimary : Color.xuTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(VietnameseDate.relativeDay(day.day, now: now, calendar: calendar)), \(MoneyFormatter.spoken(day.total))"))
                }
            }
            .frame(height: 140, alignment: .bottom)
        }
    }

    // MARK: - Danh mục

    @ViewBuilder
    private func categories(_ comparison: PeriodComparison) -> some View {
        let rows = comparison.changes.filter { $0.current > 0 }.sorted { ($0.current, $1.key) > ($1.current, $0.key) }
        if let largest = rows.first?.current {
            let catalog = CategoryCatalog(custom: customCategories)
            VStack(alignment: .leading, spacing: 14) {
                Text("Theo danh mục")
                    .font(.subheadline.weight(.semibold))
                ForEach(rows) { row in
                    let category = catalog.info(for: row.key)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            CategoryLabel(category: category)
                            Spacer()
                            Text(MoneyFormatter.short(row.current))
                                .fontWeight(.medium)
                                .money(row.current)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(category.color)
                                .frame(width: max(6, proxy.size.width * CGFloat(row.current) / CGFloat(largest)))
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                        if comparison.previousTotal > 0, row.delta != 0 {
                            Text(deltaText(row.delta, sameDays: isCurrentWeek))
                                .font(.caption)
                                .foregroundStyle(row.delta > 0 ? Color.red : Color.xuTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            Text("Tuần này chưa tiêu gì.")
                .foregroundStyle(Color.xuTextSecondary)
        }
    }

    /// Tuần đang diễn ra so với đúng các ngày đó của tuần trước, nên nói rõ "cùng ngày".
    private func deltaText(_ delta: Int, sameDays: Bool) -> String {
        let amount = MoneyFormatter.short(abs(delta))
        switch (sameDays, delta > 0) {
        case (true, true): return String(localized: "tăng \(amount) so với cùng ngày tuần trước")
        case (true, false): return String(localized: "giảm \(amount) so với cùng ngày tuần trước")
        case (false, true): return String(localized: "tăng \(amount) so với tuần trước")
        case (false, false): return String(localized: "giảm \(amount) so với tuần trước")
        }
    }

    private var isCurrentWeek: Bool {
        weekStart >= HistoryWindow.weekStart(of: now, calendar: calendar)
    }

    // MARK: - Chi ở đâu

    @ViewBuilder
    private func places() -> some View {
        let interval = weekInterval
        let spends = PlaceSpending.totals(allExpenses.compactMap { expense in
            guard !expense.isOutsideBudget, interval.contains(expense.date),
                  let latitude = expense.latitude, let longitude = expense.longitude else { return nil }
            return PlaceRecord(
                coordinate: Coordinate(latitude: latitude, longitude: longitude), name: expense.placeName,
                amount: expense.amount, date: expense.date, categoryKey: expense.categoryKey
            )
        })
        if !spends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Chi ở đâu nhiều nhất")
                    .font(.subheadline.weight(.semibold))
                ForEach(spends.prefix(3)) { spend in
                    HStack {
                        Label(spend.name ?? String(localized: "Chưa đặt tên"), systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MoneyFormatter.short(spend.total)).money(spend.total)
                    }
                    .foregroundStyle(Color.xuTextSecondary)
                    .frame(minHeight: 32)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WeekDetailView(weekStart: HistoryWindow.weekStart(of: Date(), calendar: .current), now: Date())
    }
    .xuPreview()
}
