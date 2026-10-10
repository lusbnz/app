import Foundation

/// Cách gọi ngày giờ trong app: "Thứ 5, 8 tháng 10", "hôm qua", "19:42".
enum VietnameseDate {
    /// Ngôn ngữ giao diện đang dùng (theo `AppleLanguages` của app). Tiếng Việt viết "thứ 4, 3 tháng 10";
    /// ngôn ngữ khác dùng tên ngày và tháng của chính ngôn ngữ đó.
    private static var languageCode: String { Bundle.main.preferredLocalizations.first ?? "vi" }
    private static var isVietnamese: Bool { languageCode.hasPrefix("vi") }

    private static func formatted(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: languageCode)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// `weekday` theo Calendar: 1 là Chủ nhật.
    static func weekdayName(_ weekday: Int) -> String {
        if weekday == 1 { return String(localized: "chủ nhật") }
        if isVietnamese { return String(localized: "thứ \(weekday)") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: languageCode)
        let names = calendar.weekdaySymbols
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : ""
    }

    /// Tiêu đề màn Tháng: "Tháng 10" hoặc "October".
    static func monthTitle(_ date: Date, calendar: Calendar) -> String {
        if isVietnamese { return String(localized: "Tháng \(calendar.component(.month, from: date))") }
        return formatted(date, template: "LLLL", calendar: calendar)
    }

    static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        if !isVietnamese { return formatted(date, template: "EEEEdMMMM", calendar: calendar) }
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
            if !isVietnamese { return Self.formatted(date, template: "dMMM", calendar: calendar) }
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
