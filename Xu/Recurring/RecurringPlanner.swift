import Foundation

enum RecurringFrequency: String, CaseIterable, Identifiable, Sendable {
    case weekly, biweekly, monthly, quarterly, yearly

    var id: String { rawValue }
}

/// Một khoản định kỳ nhìn từ phía lịch: tiền nhà, Netflix, gửi xe tuần; mỗi tuần, hai tuần, tháng, quý hoặc năm một lần.
/// Khoản hai tuần một lần bắt đầu từ thứ đã chọn đầu tiên kể từ ngày tạo (`createdAt`); khoản mỗi quý bắt đầu từ `monthOfYear`.
struct RecurringItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryKey: String
    /// 1...31, dùng cho khoản theo tháng, theo quý và theo năm. Tháng ngắn hơn thì tính vào ngày cuối tháng.
    var dayOfMonth: Int
    var isOutsideBudget: Bool
    var createdAt: Date
    /// Mã kỳ gần nhất đã ghi hoặc đã bỏ qua, rỗng nếu chưa lần nào: "2026-10" (tháng), "2026-W41" (tuần), "2026" (năm).
    /// Giữ tên `handledMonth` cho khớp dữ liệu đã lưu.
    var handledMonth: String
    var frequency: RecurringFrequency = .monthly
    /// Theo `Calendar.weekday`: 1 là Chủ nhật ... 7 là thứ Bảy. Chỉ dùng cho khoản theo tuần và hai tuần một lần.
    var weekday: Int = 2
    /// 1...12. Khoản theo năm: tháng đến hạn. Khoản theo quý: tháng đầu của chu kỳ ba tháng (4 thì nhắc vào tháng 4, 7, 10, 1).
    var monthOfYear: Int = 1
    /// Đến hạn thì Pennyline tự ghi khi mở app (vẫn qua `SaveGate.canSave`); không thì chỉ nhắc.
    var autoRecord: Bool = false
    /// Nhắc thêm một lần lúc 9:00 ngày hôm trước ngày đến hạn.
    var remindDayBefore: Bool = false
}

/// Lịch của các khoản định kỳ. Mặc định Pennyline chỉ nhắc, người dùng chạm mới ghi; khoản đặt tự ghi thì ghi khi mở app.
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

    /// Mã của kỳ chứa `date`: tháng "2026-10", tuần "2026-W41", năm "2026". Khoản hai tuần một lần dùng mã tuần,
    /// khoản mỗi quý dùng mã tháng (chỉ các tuần, tháng nằm trong chu kỳ mới có hạn).
    static func periodKey(_ date: Date, frequency: RecurringFrequency, calendar: Calendar) -> String {
        switch frequency {
        case .monthly, .quarterly:
            return monthKey(date, calendar: calendar)
        case .weekly, .biweekly:
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

    /// Bốn tháng nhắc của khoản mỗi quý bắt đầu từ `start`: 11 thì 2, 5, 8, 11. Sắp tăng dần.
    static func quarterMonths(startingAt start: Int) -> [Int] {
        let first = (min(max(1, start), 12) - 1) % 3 + 1
        return [first, first + 3, first + 6, first + 9]
    }

    /// Tuần đầu tiên có ngày đến hạn của khoản hai tuần một lần: tuần chứa thứ đã chọn đầu tiên kể từ ngày tạo.
    /// Tạo vào thứ Sáu cho "thứ Hai" thì lần đầu là thứ Hai tuần sau, rồi cứ hai tuần một lần.
    private static func firstWeek(of item: RecurringItem, calendar: Calendar) -> Date {
        let created = calendar.startOfDay(for: item.createdAt)
        let first = (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: created) }
            .first { calendar.component(.weekday, from: $0) == item.weekday }
        return HistoryWindow.weekStart(of: first ?? created, calendar: calendar)
    }

    /// Kỳ chứa `date` có nằm trong chu kỳ của khoản không: hai tuần một lần thì cách tuần đầu một số chẵn tuần,
    /// mỗi quý thì cách tháng đầu `monthOfYear` một bội số của ba tháng. Các tần suất khác luôn có.
    static func isOnCycle(_ item: RecurringItem, periodOf date: Date, calendar: Calendar) -> Bool {
        switch item.frequency {
        case .biweekly:
            let from = firstWeek(of: item, calendar: calendar)
            let to = HistoryWindow.weekStart(of: date, calendar: calendar)
            return (calendar.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 1) % 2 == 0
        case .quarterly:
            return quarterMonths(startingAt: item.monthOfYear).contains(calendar.component(.month, from: date))
        case .weekly, .monthly, .yearly:
            return true
        }
    }

    /// Đầu ngày đến hạn của kỳ chứa `date`: ngày trong tuần, ngày trong tháng, hoặc ngày và tháng trong năm.
    /// Nil khi kỳ đó không nằm trong chu kỳ (tuần lệch của khoản hai tuần một lần, tháng lệch của khoản mỗi quý).
    static func dueDate(for item: RecurringItem, inPeriodOf date: Date, calendar: Calendar) -> Date? {
        guard isOnCycle(item, periodOf: date, calendar: calendar) else { return nil }
        switch item.frequency {
        case .monthly, .quarterly:
            return dueDate(day: item.dayOfMonth, inMonthOf: date, calendar: calendar)
        case .weekly, .biweekly:
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

    /// Đơn vị kỳ và số kỳ cần nhìn tới để chắc chắn gặp ít nhất một lần đến hạn kế tiếp.
    private static func lookahead(_ frequency: RecurringFrequency) -> (unit: Calendar.Component, count: Int) {
        switch frequency {
        case .weekly: (.weekOfYear, 3)
        case .biweekly: (.weekOfYear, 5)
        case .monthly: (.month, 2)
        case .quarterly: (.month, 4)
        case .yearly: (.year, 2)
        }
    }

    /// Ngày đến hạn gần nhất từ hôm nay trở đi (chưa ghi, chưa bỏ qua, không trước ngày tạo). Dùng để cho người dùng
    /// thấy lịch mình vừa đặt rơi vào ngày nào.
    static func nextDueDate(for item: RecurringItem, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let created = calendar.startOfDay(for: item.createdAt)
        let (unit, count) = lookahead(item.frequency)
        for offset in 0..<count {
            guard let period = calendar.date(byAdding: unit, value: offset, to: now),
                  item.handledMonth != periodKey(period, frequency: item.frequency, calendar: calendar),
                  let due = dueDate(for: item, inPeriodOf: period, calendar: calendar),
                  due >= today, due >= created else { continue }
            return due
        }
        return nil
    }

    /// Lúc cần nhắc ở kỳ này và các kỳ kế tiếp (tới vài kỳ tùy tần suất), chỉ các lần chưa qua và chưa xử lý. Sớm nhất trước.
    /// Khoản bật `remindDayBefore` có thêm một lần nhắc 9:00 ngày hôm trước (`isDayBefore`).
    static func fireDates(for items: [RecurringItem], now: Date, calendar: Calendar) -> [(id: UUID, date: Date, isDayBefore: Bool)] {
        var result: [(id: UUID, date: Date, isDayBefore: Bool)] = []
        for item in items {
            let (unit, count) = lookahead(item.frequency)
            for offset in 0..<count {
                guard let period = calendar.date(byAdding: unit, value: offset, to: now),
                      item.handledMonth != periodKey(period, frequency: item.frequency, calendar: calendar),
                      let due = dueDate(for: item, inPeriodOf: period, calendar: calendar),
                      due >= calendar.startOfDay(for: item.createdAt) else { continue }
                if let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: due), fire > now {
                    result.append((item.id, fire, false))
                }
                if item.remindDayBefore,
                   let eve = calendar.date(byAdding: .day, value: -1, to: due),
                   let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: eve), fire > now {
                    result.append((item.id, fire, true))
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
