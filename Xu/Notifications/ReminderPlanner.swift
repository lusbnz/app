import Foundation

/// Lịch nhắc ghi lúc 21:00. Thông báo cục bộ không tự kiểm tra điều kiện lúc nổ,
/// nên app xếp sẵn từng ngày và bỏ ngày hôm nay ngay khi có khoản được ghi.
enum ReminderPlanner {
    static let hour = 21

    static func fireDates(now: Date, hasLoggedToday: Bool, days: Int = 14, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now else { return nil }
            if offset == 0, hasLoggedToday { return nil }
            return fire
        }
    }
}
