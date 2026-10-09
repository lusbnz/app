import Foundation

/// Gợi ý theo giờ: những khoản hay ghi vào buổi này trong 30 ngày gần nhất.
enum TimeSuggester {
    static let windowDays = 30
    /// Phải xuất hiện ít nhất bấy nhiêu lần trong cùng buổi mới gọi là "hay ghi".
    static let minimumOccurrences = 2

    static func suggestions(records: [SuggestionRecord], now: Date, calendar: Calendar, limit: Int = 3) -> [Suggestion] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) else { return [] }
        let part = PartOfDay.of(now, calendar: calendar)
        let weekday = calendar.component(.weekday, from: now)
        let loggedToday = records.loggedIDs(on: now, calendar: calendar)

        var table: [String: (suggestion: Suggestion, occurrences: Int, score: Int, latest: Date)] = [:]
        for record in records where record.date >= windowStart && record.date < today {
            guard PartOfDay.of(record.date, calendar: calendar) == part else { continue }
            let suggestion = Suggestion(name: record.name, amount: record.amount, categoryKey: record.categoryKey)
            guard !suggestion.name.isEmpty, !loggedToday.contains(suggestion.id) else { continue }
            var entry = table[suggestion.id] ?? (suggestion, 0, 0, .distantPast)
            entry.occurrences += 1
            entry.score += calendar.component(.weekday, from: record.date) == weekday ? 2 : 1
            if record.date >= entry.latest {
                entry.latest = record.date
                entry.suggestion = suggestion
            }
            table[suggestion.id] = entry
        }
        return table.values
            .filter { $0.occurrences >= minimumOccurrences }
            .sorted { ($0.score, $0.latest) > ($1.score, $1.latest) }
            .prefix(limit)
            .map(\.suggestion)
    }

    /// "12:15 · trưa thứ 5 bạn hay ghi"
    static func label(now: Date, calendar: Calendar) -> String {
        let time = VietnameseDate.time(now, calendar: calendar)
        let part = PartOfDay.of(now, calendar: calendar).title
        let weekday = VietnameseDate.weekdayName(calendar.component(.weekday, from: now))
        return String(localized: "\(time) · \(part) \(weekday) bạn hay ghi")
    }
}
