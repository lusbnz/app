import Foundation

enum RecurringFrequency: String, CaseIterable, Identifiable, Sendable {
    case weekly, monthly, yearly

    var id: String { rawValue }
}

/// Một khoản định kỳ nhìn từ phía lịch: tiền nhà, Netflix, gửi xe tuần; mỗi tuần, tháng hoặc năm một lần.
struct RecurringItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryKey: String
    /// 1...31, dùng cho khoản theo tháng và theo năm. Tháng ngắn hơn thì tính vào ngày cuối tháng.
    var dayOfMonth: Int
    var isOutsideBudget: Bool
    var createdAt: Date
    /// Mã kỳ gần nhất đã ghi hoặc đã bỏ qua, rỗng nếu chưa lần nào: "2026-10" (tháng), "2026-W41" (tuần), "2026" (năm).
    /// Giữ tên `handledMonth` cho khớp dữ liệu đã lưu.
    var handledMonth: String
    var frequency: RecurringFrequency = .monthly
    /// Theo `Calendar.weekday`: 1 là Chủ nhật ... 7 là thứ Bảy. Chỉ dùng cho khoản theo tuần.
    var weekday: Int = 2
    /// 1...12, chỉ dùng cho khoản theo năm.
    var monthOfYear: Int = 1
    /// Đến hạn thì Nhẩm tự ghi khi mở app (vẫn qua `SaveGate.canSave`); không thì chỉ nhắc.
    var autoRecord: Bool = false
}

/// Lịch của các khoản định kỳ. Mặc định Nhẩm chỉ nhắc, người dùng chạm mới ghi; khoản đặt tự ghi thì ghi khi mở app.
enum RecurringPlanner {
    static let reminderHour = 9

    static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(String(format: "%02d", parts.month ?? 0))"
    }

    /// "2026-10-09": mã của riêng một ngày, để đặt tên lời nhắc.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(String(format: "%02d", parts.month ?? 0))-\(String(format: "%02d", parts.day ?? 0))"
    }

    /// Mã của kỳ chứa `date`: tháng "2026-10", tuần "2026-W41", năm "2026".
    static func periodKey(_ date: Date, frequency: RecurringFrequency, calendar: Calendar) -> String {
        switch frequency {
        case .monthly:
            return monthKey(date, calendar: calendar)
        case .weekly:
            let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return "\(parts.yearForWeekOfYear ?? 0)-W\(String(format: "%02d", parts.weekOfYear ?? 0))"
        case .yearly:
            return "\(calendar.component(.year, from: date))"
        }
    }

    /// Đầu ngày đến hạn trong tháng của `date`; ngày 31 ở tháng 30 ngày thì lùi về ngày 30.
    static func dueDate(day: Int, inMonthOf date: Date, calendar: Calendar) -> Date? {
        guard let days = calendar.range(of: .day, in: .month, for: date)?.count,
              let month = calendar.dateInterval(of: .month, for: date) else { return nil }
        let clamped = min(max(1, day), days)
        return calendar.date(byAdding: .day, value: clamped - 1, to: month.start)
    }

    /// Đầu ngày đến hạn của kỳ chứa `date`: ngày trong tuần, ngày trong tháng, hoặc ngày và tháng trong năm.
    static func dueDate(for item: RecurringItem, inPeriodOf date: Date, calendar: Calendar) -> Date? {
        switch item.frequency {
        case .monthly:
            return dueDate(day: item.dayOfMonth, inMonthOf: date, calendar: calendar)
        case .weekly:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
            return (0..<7)
                .compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
                .first { calendar.component(.weekday, from: $0) == item.weekday }
        case .yearly:
            let year = calendar.component(.year, from: date)
            guard let first = calendar.date(from: DateComponents(year: year, month: min(max(1, item.monthOfYear), 12), day: 1)) else { return nil }
            return dueDate(day: item.dayOfMonth, inMonthOf: first, calendar: calendar)
        }
    }

    /// Đã đến hạn trong kỳ này mà chưa ghi hay bỏ qua. Khoản tạo sau ngày đến hạn của kỳ này thì chờ kỳ sau.
    static func isDue(_ item: RecurringItem, now: Date, calendar: Calendar) -> Bool {
        guard item.handledMonth != periodKey(now, frequency: item.frequency, calendar: calendar),
              let due = dueDate(for: item, inPeriodOf: now, calendar: calendar) else { return false }
        return due <= now && due >= calendar.startOfDay(for: item.createdAt)
    }

    /// Ngày phát sinh của khoản được ghi: đến hạn từ hôm trước thì tính ngày đó (buổi trưa), không thì lúc này.
    static func expenseDate(for item: RecurringItem, now: Date, calendar: Calendar) -> Date {
        guard let due = dueDate(for: item, inPeriodOf: now, calendar: calendar),
              due < calendar.startOfDay(for: now) else { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: due) ?? now
    }

    /// Lúc cần nhắc ở kỳ này và các kỳ kế tiếp (2 tháng, 3 tuần, hoặc 2 năm), chỉ các lần chưa qua và chưa xử lý.
    /// Sớm nhất trước.
    static func fireDates(for items: [RecurringItem], now: Date, calendar: Calendar) -> [(id: UUID, date: Date)] {
        var result: [(id: UUID, date: Date)] = []
        for item in items {
            let (unit, count): (Calendar.Component, Int) = switch item.frequency {
            case .weekly: (.weekOfYear, 3)
            case .monthly: (.month, 2)
            case .yearly: (.year, 2)
            }
            for offset in 0..<count {
                guard let period = calendar.date(byAdding: unit, value: offset, to: now),
                      item.handledMonth != periodKey(period, frequency: item.frequency, calendar: calendar),
                      let due = dueDate(for: item, inPeriodOf: period, calendar: calendar),
                      due >= calendar.startOfDay(for: item.createdAt),
                      let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: due),
                      fire > now else { continue }
                result.append((item.id, fire))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
