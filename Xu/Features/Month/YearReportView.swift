import SwiftData
import SwiftUI

/// Báo cáo năm (Pennyline Pro): tổng cả năm, từng tháng, danh mục, khoản và nơi tốn nhiều nhất; xuất được ra PDF.
struct YearReportView: View {
    @Environment(\.calendar) private var calendar
    /// Không lọc trong `@Query`: màn hình nằm trong `navigationDestination` sẽ truy vấn lại liên tục (xem `MonthView`).
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var customCategories: [CustomCategory]
    @State private var year: Int

    let now: Date

    init(now: Date) {
        self.now = now
        _year = State(initialValue: Calendar.current.component(.year, from: now))
    }

    var body: some View {
        let records = allExpenses.map(\.record)
        let report = YearReport.make(records: records, year: year, now: now, calendar: calendar)
        let catalog = CategoryCatalog(custom: customCategories)
        // Năm nay luôn chọn được, kể cả khi chưa có khoản nào.
        let years = Set(YearReport.availableYears(records: records, calendar: calendar) + [calendar.component(.year, from: now)])
            .sorted(by: >)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(report)
                if report.count > 0 {
                    monthBars(report)
                    categories(report, catalog: catalog)
                    ranking("Tốn nhiều nhất", report.topNames)
                    ranking("Chi ở đâu nhiều nhất", report.topPlaces)
                    highlights(report)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .xuScreen()
        .navigationTitle("Báo cáo năm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Năm", selection: $year) {
                    ForEach(years, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: YearReportExport(report: report, categoryTitles: catalog.titles),
                    preview: SharePreview(YearReportPDF.fileName(year: report.year))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(report.count == 0)
                .accessibilityLabel("Xuất PDF")
            }
        }
    }

    // MARK: - Phần đầu

    private func header(_ report: YearReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Năm \(String(report.year))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.xuTextSecondary)
            HighlightedNumber(text: MoneyFormatter.short(report.total), fraction: report.count > 0 ? 1 : 0, size: 64)
            if report.count == 0 {
                Text("Năm này chưa có khoản chi nào.")
                    .foregroundStyle(Color.xuTextSecondary)
            } else {
                Text(YearReportText.summary(report))
                    .foregroundStyle(Color.xuTextSecondary)
                if let change = YearReportText.change(report) {
                    Text(change)
                        .foregroundStyle((report.changePercent ?? 0) > 0 ? Color.red : Color.xuTextSecondary)
                }
                if report.outsideBudgetTotal > 0 {
                    Text("Trong đó \(MoneyFormatter.short(report.outsideBudgetTotal)) ngoài ngân sách.")
                        .foregroundStyle(Color.xuTextSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Từng tháng

    private func monthBars(_ report: YearReport) -> some View {
        let largest = max(1, report.months.map(\.total).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Từng tháng")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(report.months) { month in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(month.month == report.busiestMonth ? Color.xuHighlight : Color.xuButton)
                            .frame(height: month.total > 0 ? max(4, 110 * CGFloat(month.total) / CGFloat(largest)) : 2)
                            .frame(maxHeight: 110, alignment: .bottom)
                        Text(verbatim: "\(month.month)")
                            .font(.caption2)
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Tháng \(month.month): \(MoneyFormatter.spoken(month.total))"))
                }
            }
            if let busiest = report.busiestMonth {
                Text("Tháng \(busiest) tiêu nhiều nhất: \(MoneyFormatter.short(report.months[busiest - 1].total)).")
                    .font(.footnote)
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
    }

    // MARK: - Danh mục

    private func categories(_ report: YearReport, catalog: CategoryCatalog) -> some View {
        let largest = max(1, report.byCategory.first?.total ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Danh mục")
                .font(.subheadline.weight(.semibold))
            ForEach(report.byCategory) { group in
                let category = catalog.info(for: group.key)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        CategoryLabel(category: category)
                        Spacer()
                        Text(verbatim: "\(report.share(of: group))%")
                            .foregroundStyle(Color.xuTextSecondary)
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
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Xếp hạng

    @ViewBuilder
    private func ranking(_ title: LocalizedStringKey, _ groups: [YearReport.Group]) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "\(index + 1)")
                            .foregroundStyle(Color.xuTextSecondary)
                            .frame(width: 22, alignment: .leading)
                        Text(verbatim: group.label)
                        Text("\(group.count) lần")
                            .font(.caption)
                            .foregroundStyle(Color.xuTextSecondary)
                        Spacer()
                        Text(MoneyFormatter.short(group.total))
                            .fontWeight(.medium)
                            .money(group.total)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Điểm đáng nhớ

    private func highlights(_ report: YearReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Đáng nhớ")
                .font(.subheadline.weight(.semibold))
            ForEach(YearReportText.highlights(report, calendar: calendar), id: \.self) { line in
                Text(verbatim: line)
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
    }
}

/// Câu chữ của báo cáo năm, dùng chung cho màn hình và bản PDF.
enum YearReportText {
    /// "1.234 khoản, trung bình 7,2tr mỗi tháng."
    static func summary(_ report: YearReport) -> String {
        String(localized: "\(report.count) khoản, trung bình \(MoneyFormatter.short(report.averagePerMonth)) mỗi tháng.")
    }

    /// "Tăng 12% so với cùng kỳ năm trước."; nil khi năm trước không có gì để so.
    static func change(_ report: YearReport) -> String? {
        guard let percent = report.changePercent else { return nil }
        if percent == 0 {
            return report.isPartial ? String(localized: "Gần bằng cùng kỳ năm trước.") : String(localized: "Gần bằng năm trước.")
        }
        let amount = abs(percent)
        switch (percent > 0, report.isPartial) {
        case (true, true): return String(localized: "Tăng \(amount)% so với cùng kỳ năm trước.")
        case (true, false): return String(localized: "Tăng \(amount)% so với năm trước.")
        case (false, true): return String(localized: "Giảm \(amount)% so với cùng kỳ năm trước.")
        case (false, false): return String(localized: "Giảm \(amount)% so với năm trước.")
        }
    }

    static func highlights(_ report: YearReport, calendar: Calendar) -> [String] {
        var lines: [String] = []
        if let largest = report.largest {
            let name = largest.name.isEmpty ? String(localized: "khoản chi") : largest.name
            let parts = calendar.dateComponents([.day, .month], from: largest.date)
            lines.append(String(localized: "Khoản lớn nhất: \(name), \(MoneyFormatter.short(largest.amount)) (ngày \(parts.day ?? 1)/\(parts.month ?? 1))."))
        }
        if let quietest = report.quietestMonth, quietest != report.busiestMonth {
            lines.append(String(localized: "Tháng tiêu ít nhất: tháng \(quietest), \(MoneyFormatter.short(report.months[quietest - 1].total))."))
        }
        lines.append(String(localized: "Bạn đã ghi vào \(report.activeDays) ngày trong năm."))
        return lines
    }
}

#Preview {
    NavigationStack { YearReportView(now: Date()) }
        .xuPreview()
}
