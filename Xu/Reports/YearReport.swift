import Foundation

/// Tổng kết chi tiêu của một năm. Gồm mọi khoản chi (cả ngoài ngân sách), vì đây là bức tranh cả năm chứ không phải hạn mức.
struct YearReport: Equatable, Sendable {
    struct Month: Equatable, Sendable, Identifiable {
        /// 1...12
        var month: Int
        var total: Int
        var count: Int

        var id: Int { month }
    }

    struct Group: Equatable, Sendable, Identifiable {
        /// Khóa danh mục, tên khoản đã chuẩn hóa, hoặc tên nơi đã chuẩn hóa.
        var key: String
        /// Chữ để hiện: với danh mục thì trùng `key` (tầng giao diện tra tên), còn lại là chữ người dùng gõ lần gần nhất.
        var label: String
        var total: Int
        var count: Int

        var id: String { key }
    }

    var year: Int
    var total: Int
    var outsideBudgetTotal: Int
    var count: Int
    /// Đủ 12 tháng, tháng không có khoản nào thì tổng là 0.
    var months: [Month]
    /// Giảm dần theo tổng.
    var byCategory: [Group]
    /// Tối đa 10 tên khoản tốn nhiều nhất.
    var topNames: [Group]
    /// Tối đa 5 nơi tốn nhiều nhất (chỉ khoản có tên nơi).
    var topPlaces: [Group]
    var largest: SpendingRecord?
    /// Tháng chi nhiều nhất trong các tháng có chi; nil khi cả năm chưa có khoản nào.
    var busiestMonth: Int?
    /// Tháng chi ít nhất trong các tháng có chi và đã trọn (tháng đang dở của năm nay không tính, vì nó ít chỉ do chưa hết tháng).
    var quietestMonth: Int?
    /// Số tháng dùng để tính trung bình: từ tháng có khoản đầu tiên tới hết năm, hoặc tới tháng này nếu là năm nay.
    var monthsCounted: Int
    /// Số ngày có ghi ít nhất một khoản.
    var activeDays: Int
    /// Năm đang xem chưa hết (là năm nay), nên so sánh là so với cùng đoạn ngày của năm trước.
    var isPartial: Bool
    /// Tổng của năm trước trong cùng đoạn ngày; nil khi năm trước không có khoản nào trong đoạn đó.
    var previousTotal: Int?

    var averagePerMonth: Int { monthsCounted > 0 ? total / monthsCounted : 0 }

    /// Phần trăm thay đổi so với năm trước, làm tròn số nguyên; nil khi không có gì để so.
    var changePercent: Int? {
        guard let previousTotal, previousTotal > 0 else { return nil }
        let delta = total - previousTotal
        return (delta * 100 + (delta >= 0 ? previousTotal / 2 : -previousTotal / 2)) / previousTotal
    }

    /// Phần của một nhóm trong tổng cả năm, 0...100.
    func share(of group: Group) -> Int {
        total > 0 ? (group.total * 100 + total / 2) / total : 0
    }

    // MARK: - Dựng

    /// Các năm có khoản chi, mới nhất trước.
    static func availableYears(records: [SpendingRecord], calendar: Calendar) -> [Int] {
        Set(records.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }

    static func make(records: [SpendingRecord], year: Int, now: Date, calendar: Calendar) -> YearReport {
        let currentYear = calendar.component(.year, from: now)
        let isPartial = year == currentYear
        let inYear = records
            .filter { calendar.component(.year, from: $0.date) == year && (!isPartial || $0.date <= now) }
            .sorted { $0.date < $1.date }

        var months = (1...12).map { Month(month: $0, total: 0, count: 0) }
        var days = Set<Date>()
        for record in inYear {
            let index = calendar.component(.month, from: record.date) - 1
            months[index].total += record.amount
            months[index].count += 1
            days.insert(calendar.startOfDay(for: record.date))
        }
        let spending = months.filter { $0.count > 0 }
        let firstMonth = spending.first?.month
        let lastMonth = isPartial ? calendar.component(.month, from: now) : 12
        let finished = spending.filter { !isPartial || $0.month < lastMonth }

        // Cùng đoạn ngày của năm trước: cả năm, hoặc từ đầu năm tới đúng ngày này năm trước khi năm đang xem chưa hết.
        let previousEnd = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let previous = records.filter {
            calendar.component(.year, from: $0.date) == year - 1 && (!isPartial || $0.date <= previousEnd)
        }

        return YearReport(
            year: year,
            total: inYear.reduce(0) { $0 + $1.amount },
            outsideBudgetTotal: inYear.filter(\.isOutsideBudget).reduce(0) { $0 + $1.amount },
            count: inYear.count,
            months: months,
            byCategory: groups(inYear) { ($0.categoryKey, $0.categoryKey) },
            topNames: Array(groups(inYear) { (TextNormalizer.keyword($0.name), $0.name) }.prefix(10)),
            topPlaces: Array(groups(inYear) { record in
                let place = record.placeName ?? ""
                return (TextNormalizer.keyword(place), place)
            }.prefix(5)),
            largest: inYear.max { ($0.amount, $1.date) < ($1.amount, $0.date) },
            busiestMonth: spending.max { ($0.total, $1.month) < ($1.total, $0.month) }?.month,
            quietestMonth: finished.min { ($0.total, $0.month) < ($1.total, $1.month) }?.month,
            monthsCounted: firstMonth.map { max(1, lastMonth - $0 + 1) } ?? 0,
            activeDays: days.count,
            isPartial: isPartial,
            previousTotal: previous.isEmpty ? nil : previous.reduce(0) { $0 + $1.amount }
        )
    }

    /// Gom theo khóa, bỏ khóa rỗng; nhãn là chữ của lần gần nhất. Giảm dần theo tổng, hòa thì theo khóa.
    private static func groups(_ records: [SpendingRecord], key: (SpendingRecord) -> (key: String, label: String)) -> [Group] {
        var table: [String: Group] = [:]
        for record in records {
            let (key, label) = key(record)
            guard !key.isEmpty else { continue }
            var group = table[key] ?? Group(key: key, label: label, total: 0, count: 0)
            group.label = label
            group.total += record.amount
            group.count += 1
            table[key] = group
        }
        return table.values.sorted { ($0.total, $1.key) > ($1.total, $0.key) }
    }
}
