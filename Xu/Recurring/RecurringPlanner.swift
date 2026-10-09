import Foundation

/// Một khoản định kỳ nhìn từ phía lịch: tiền nhà, Netflix, mỗi tháng một lần vào một ngày cố định.
struct RecurringItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryKey: String
    /// 1...31. Tháng ngắn hơn thì tính vào ngày cuối tháng.
    var dayOfMonth: Int
    var isOutsideBudget: Bool
    var createdAt: Date
    /// "2026-10": tháng gần nhất đã ghi hoặc đã bỏ qua; rỗng nếu chưa lần nào.
    var handledMonth: String
}

/// Lịch của các khoản định kỳ. Xu chỉ nhắc, người dùng chạm mới ghi.
enum RecurringPlanner {
    static let reminderHour = 9

    static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(String(format: "%02d", parts.month ?? 0))"
    }

    /// Đầu ngày đến hạn trong tháng của `date`; ngày 31 ở tháng 30 ngày thì lùi về ngày 30.
    static func dueDate(day: Int, inMonthOf date: Date, calendar: Calendar) -> Date? {
        guard let days = calendar.range(of: .day, in: .month, for: date)?.count,
              let month = calendar.dateInterval(of: .month, for: date) else { return nil }
        let clamped = min(max(1, day), days)
        return calendar.date(byAdding: .day, value: clamped - 1, to: month.start)
    }

    /// Đã đến hạn trong tháng này mà chưa ghi hay bỏ qua. Khoản tạo sau ngày đến hạn của tháng này thì chờ tháng sau.
    static func isDue(_ item: RecurringItem, now: Date, calendar: Calendar) -> Bool {
        guard item.handledMonth != monthKey(now, calendar: calendar),
              let due = dueDate(day: item.dayOfMonth, inMonthOf: now, calendar: calendar) else { return false }
        return due <= now && due >= calendar.startOfDay(for: item.createdAt)
    }

    /// Ngày phát sinh của khoản được ghi: đến hạn từ hôm trước thì tính ngày đó (buổi trưa), không thì lúc này.
    static func expenseDate(for item: RecurringItem, now: Date, calendar: Calendar) -> Date {
        guard let due = dueDate(day: item.dayOfMonth, inMonthOf: now, calendar: calendar),
              due < calendar.startOfDay(for: now) else { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: due) ?? now
    }

    /// Lúc cần nhắc trong tháng này và tháng sau, chỉ các lần chưa qua và chưa xử lý. Sớm nhất trước.
    static func fireDates(for items: [RecurringItem], now: Date, calendar: Calendar) -> [(id: UUID, date: Date)] {
        var result: [(id: UUID, date: Date)] = []
        for item in items {
            for offset in 0..<2 {
                guard let month = calendar.date(byAdding: .month, value: offset, to: now),
                      item.handledMonth != monthKey(month, calendar: calendar),
                      let due = dueDate(day: item.dayOfMonth, inMonthOf: month, calendar: calendar),
                      due >= calendar.startOfDay(for: item.createdAt),
                      let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: due),
                      fire > now else { continue }
                result.append((item.id, fire))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
