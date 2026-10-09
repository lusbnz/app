import Foundation

/// Cách gọi ngày giờ trong app: "Thứ 5, 8 tháng 10", "hôm qua", "19:42".
enum VietnameseDate {
    /// `weekday` theo Calendar: 1 là Chủ nhật.
    static func weekdayName(_ weekday: Int) -> String {
        weekday == 1 ? String(localized: "chủ nhật") : String(localized: "thứ \(weekday)")
    }

    static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekday = weekdayName(parts.weekday ?? 1)
        let title = String(localized: "\(weekday), \(parts.day ?? 1) tháng \(parts.month ?? 1)")
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// "hôm nay", "hôm qua", "hôm kia", rồi thứ trong tuần, xa hơn thì "3 tháng 10".
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case 0: return String(localized: "hôm nay")
        case 1: return String(localized: "hôm qua")
        case 2: return String(localized: "hôm kia")
        case 3...6: return weekdayName(calendar.component(.weekday, from: date))
        default:
            let parts = calendar.dateComponents([.day, .month], from: date)
            return String(localized: "\(parts.day ?? 1) tháng \(parts.month ?? 1)")
        }
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return "\(parts.hour ?? 0):\(minute < 10 ? "0" : "")\(minute)"
    }

    /// "hôm qua, 19:42"
    static func dayAndTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        "\(relativeDay(date, now: now, calendar: calendar)), \(time(date, calendar: calendar))"
    }
}
