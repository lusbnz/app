import Foundation

/// Một khoản chi nhìn từ phía công thức ngân sách.
struct BudgetEntry: Equatable, Sendable {
    var amount: Int
    var date: Date
    var isOutsideBudget: Bool = false
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

    var remainingToday: Int { allowanceToday - spentToday }
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
