import Foundation

/// Một khoản chi nhìn từ phía công thức ngân sách.
struct BudgetEntry: Equatable, Sendable {
    var amount: Int
    var date: Date
    var isOutsideBudget: Bool = false
    /// Chỉ cần khi tính hạn mức danh mục vào hạn mức ngày.
    var categoryKey: String = ""
}

struct BudgetStatus: Equatable, Sendable {
    /// Ngân sách của kỳ đang tính (một tháng hoặc một tuần).
    var budget: Int
    var period: BudgetPeriod = .month
    var spentBeforeToday: Int
    var spentToday: Int
    /// Số ngày từ hôm nay đến cuối kỳ, tính cả hôm nay.
    var daysLeft: Int
    /// Số ngày từ đầu kỳ đến hôm nay, tính cả hôm nay.
    var daysElapsed: Int = 1
    var allowanceToday: Int
    /// nil vào ngày cuối kỳ.
    var allowanceTomorrow: Int?
    /// Phần chi hôm nay tính vào hạn mức ngày. nil nghĩa là bằng `spentToday`; khác khi hạn mức
    /// danh mục giữ riêng một phần tiền (chi trong hạn mức của danh mục không trừ vào hạn mức chung).
    var countedToday: Int? = nil

    var remainingToday: Int { allowanceToday - (countedToday ?? spentToday) }
    var spentThisPeriod: Int { spentBeforeToday + spentToday }
    var remainingThisPeriod: Int { budget - spentThisPeriod }

    /// Tỉ lệ hạn mức hôm nay còn lại, từ 0 đến 1.
    var todayFraction: Double { Self.fraction(remainingToday, of: allowanceToday) }
    /// Tỉ lệ ngân sách của kỳ còn lại, từ 0 đến 1.
    var periodFraction: Double { Self.fraction(remainingThisPeriod, of: budget) }

    private static func fraction(_ part: Int, of whole: Int) -> Double {
        guard whole > 0, part > 0 else { return 0 }
        return min(1, Double(part) / Double(whole))
    }
}

struct BudgetForecast: Equatable, Sendable {
    var pacePerDay: Int
    /// Số dư cuối kỳ nếu giữ nhịp này; âm nghĩa là vượt.
    var projectedLeftover: Int
}

enum BudgetCalculator {
    /// Còn được tiêu bao nhiêu hôm nay. `budget` là ngân sách của một kỳ (tháng hoặc tuần); hạn mức ngày là phần
    /// còn lại của kỳ chia đều cho số ngày còn lại.
    ///
    /// Với `categoryLimits` (chỉ khi tính theo tháng), hạn mức của từng danh mục được giữ riêng: hạn mức ngày chỉ tính
    /// trên phần ngân sách còn lại sau khi trừ các hạn mức ấy, và khoản chi trong hạn mức của danh mục không làm hạn mức
    /// ngày tụt. Chi vượt hạn mức danh mục thì trừ vào hạn mức chung. Tổng đã tiêu và còn lại của kỳ vẫn là số thật.
    static func status(
        budget: Int, period: BudgetPeriod = .month, entries: [BudgetEntry], categoryLimits: [String: Int] = [:],
        now: Date, calendar: Calendar
    ) -> BudgetStatus {
        var plain = plainStatus(budget: budget, period: period, entries: entries, now: now, calendar: calendar)
        let limits = categoryLimits.filter { $0.value > 0 }
        guard period == .month, !limits.isEmpty else { return plain }

        let month = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        var running: [String: Int] = [:]
        var free: [BudgetEntry] = []
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard !entry.isOutsideBudget, month.contains(entry.date), let limit = limits[entry.categoryKey] else {
                free.append(entry)
                continue
            }
            let before = running[entry.categoryKey, default: 0]
            let after = before + entry.amount
            running[entry.categoryKey] = after
            var counted = entry
            counted.amount = max(0, after - limit) - max(0, before - limit)
            free.append(counted)
        }
        let reserved = limits.values.reduce(0, +)
        let adjusted = plainStatus(budget: max(0, budget - reserved), period: .month, entries: free, now: now, calendar: calendar)
        plain.allowanceToday = adjusted.allowanceToday
        plain.allowanceTomorrow = adjusted.allowanceTomorrow
        plain.countedToday = adjusted.spentToday
        return plain
    }

    static func status(
        _ setting: BudgetSetting, entries: [BudgetEntry], categoryLimits: [String: Int] = [:], now: Date, calendar: Calendar
    ) -> BudgetStatus {
        status(
            budget: setting.amount, period: setting.period, entries: entries, categoryLimits: categoryLimits,
            now: now, calendar: calendar
        )
    }

    private static func plainStatus(
        budget: Int, period: BudgetPeriod, entries: [BudgetEntry], now: Date, calendar: Calendar
    ) -> BudgetStatus {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let interval = period.interval(containing: now, calendar: calendar) ?? DateInterval(start: today, end: tomorrow)

        var spentBeforeToday = 0
        var spentToday = 0
        for entry in entries where !entry.isOutsideBudget && entry.date >= interval.start && entry.date < tomorrow {
            if entry.date < today {
                spentBeforeToday += entry.amount
            } else {
                spentToday += entry.amount
            }
        }

        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: interval.end).day ?? 1)
        let daysElapsed = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: interval.start), to: today).day ?? 0) + 1)
        let allowanceToday = floorToThousand((budget - spentBeforeToday) / daysLeft)
        let allowanceTomorrow = daysLeft > 1
            ? floorToThousand((budget - spentBeforeToday - spentToday) / (daysLeft - 1))
            : nil
        return BudgetStatus(
            budget: budget,
            period: period,
            spentBeforeToday: spentBeforeToday,
            spentToday: spentToday,
            daysLeft: daysLeft,
            daysElapsed: daysElapsed,
            allowanceToday: allowanceToday,
            allowanceTomorrow: allowanceTomorrow
        )
    }

    /// Nhịp tiêu trung bình từ đầu kỳ và số dư dự kiến cuối kỳ.
    static func forecast(for status: BudgetStatus) -> BudgetForecast {
        let pace = status.spentThisPeriod / max(1, status.daysElapsed)
        return BudgetForecast(
            pacePerDay: pace,
            projectedLeftover: status.remainingThisPeriod - pace * (status.daysLeft - 1)
        )
    }

    /// Hạn mức ngày ước tính cho một ngân sách của một kỳ, dùng ở màn hình lần đầu mở app và để so các ngày cũ.
    static func dailyAverage(budget: Int, period: BudgetPeriod = .month, now: Date, calendar: Calendar) -> Int {
        floorToThousand(budget / max(1, period.dayCount(containing: now, calendar: calendar)))
    }

    /// Tổng chi trong ngân sách của từng ngày trước hôm nay, gần nhất đứng trước.
    static func previousDayTotals(entries: [BudgetEntry], days: Int, now: Date, calendar: Calendar) -> [(day: Date, total: Int)] {
        let today = calendar.startOfDay(for: now)
        return (1...max(1, days)).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let total = entries
                .filter { !$0.isOutsideBudget && $0.date >= start && $0.date < end }
                .reduce(0) { $0 + $1.amount }
            return (start, total)
        }
    }

    /// Làm tròn xuống bội số 1.000đ, kể cả với số âm.
    static func floorToThousand(_ amount: Int) -> Int {
        let quotient = amount / 1_000
        return (amount % 1_000 < 0 ? quotient - 1 : quotient) * 1_000
    }
}
