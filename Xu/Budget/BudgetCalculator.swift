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
    var monthlyBudget: Int
    var spentBeforeToday: Int
    var spentToday: Int
    /// Số ngày từ hôm nay đến cuối tháng, tính cả hôm nay.
    var daysLeft: Int
    var allowanceToday: Int
    /// nil vào ngày cuối tháng.
    var allowanceTomorrow: Int?
    /// Phần chi hôm nay tính vào hạn mức ngày. nil nghĩa là bằng `spentToday`; khác khi hạn mức
    /// danh mục giữ riêng một phần tiền (chi trong hạn mức của danh mục không trừ vào hạn mức chung).
    var countedToday: Int? = nil

    var remainingToday: Int { allowanceToday - (countedToday ?? spentToday) }
    var spentThisMonth: Int { spentBeforeToday + spentToday }
    var remainingThisMonth: Int { monthlyBudget - spentThisMonth }

    /// Tỉ lệ hạn mức hôm nay còn lại, từ 0 đến 1.
    var todayFraction: Double { Self.fraction(remainingToday, of: allowanceToday) }
    /// Tỉ lệ ngân sách tháng còn lại, từ 0 đến 1.
    var monthFraction: Double { Self.fraction(remainingThisMonth, of: monthlyBudget) }

    private static func fraction(_ part: Int, of whole: Int) -> Double {
        guard whole > 0, part > 0 else { return 0 }
        return min(1, Double(part) / Double(whole))
    }
}

struct BudgetForecast: Equatable, Sendable {
    var pacePerDay: Int
    /// Số dư cuối tháng nếu giữ nhịp này; âm nghĩa là vượt.
    var projectedLeftover: Int
}

enum BudgetCalculator {
    static func status(monthlyBudget: Int, entries: [BudgetEntry], now: Date, calendar: Calendar) -> BudgetStatus {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let month = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: today, end: tomorrow)

        var spentBeforeToday = 0
        var spentToday = 0
        for entry in entries where !entry.isOutsideBudget && entry.date >= month.start && entry.date < tomorrow {
            if entry.date < today {
                spentBeforeToday += entry.amount
            } else {
                spentToday += entry.amount
            }
        }

        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: month.end).day ?? 1)
        let allowanceToday = floorToThousand((monthlyBudget - spentBeforeToday) / daysLeft)
        let allowanceTomorrow = daysLeft > 1
            ? floorToThousand((monthlyBudget - spentBeforeToday - spentToday) / (daysLeft - 1))
            : nil
        return BudgetStatus(
            monthlyBudget: monthlyBudget,
            spentBeforeToday: spentBeforeToday,
            spentToday: spentToday,
            daysLeft: daysLeft,
            allowanceToday: allowanceToday,
            allowanceTomorrow: allowanceTomorrow
        )
    }

    /// Như `status`, nhưng hạn mức của từng danh mục được giữ riêng: hạn mức ngày chỉ tính trên phần ngân sách
    /// còn lại sau khi trừ các hạn mức ấy, và khoản chi trong hạn mức của danh mục không làm hạn mức ngày
    /// tụt. Chi vượt hạn mức danh mục thì trừ vào hạn mức chung. Tổng đã tiêu và còn lại của tháng vẫn là số thật.
    static func status(
        monthlyBudget: Int, entries: [BudgetEntry], categoryLimits: [String: Int], now: Date, calendar: Calendar
    ) -> BudgetStatus {
        var plain = status(monthlyBudget: monthlyBudget, entries: entries, now: now, calendar: calendar)
        let limits = categoryLimits.filter { $0.value > 0 }
        guard !limits.isEmpty else { return plain }

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
        let adjusted = status(monthlyBudget: max(0, monthlyBudget - reserved), entries: free, now: now, calendar: calendar)
        plain.allowanceToday = adjusted.allowanceToday
        plain.allowanceTomorrow = adjusted.allowanceTomorrow
        plain.countedToday = adjusted.spentToday
        return plain
    }

    /// Nhịp tiêu trung bình từ đầu tháng và số dư dự kiến cuối tháng.
    static func forecast(for status: BudgetStatus, now: Date, calendar: Calendar) -> BudgetForecast {
        let daysElapsed = max(1, calendar.component(.day, from: now))
        let pace = status.spentThisMonth / daysElapsed
        return BudgetForecast(
            pacePerDay: pace,
            projectedLeftover: status.remainingThisMonth - pace * (status.daysLeft - 1)
        )
    }

    /// Hạn mức ngày ước tính cho một ngân sách tháng, dùng ở màn hình lần đầu mở app.
    static func dailyAverage(monthlyBudget: Int, now: Date, calendar: Calendar) -> Int {
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return floorToThousand(monthlyBudget / days)
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
