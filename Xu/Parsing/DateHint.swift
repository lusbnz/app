import Foundation

/// Nhận cụm chỉ ngày trong một khoản chi: `hôm qua`, `tối qua`, `sáng nay`, `3 ngày trước`,
/// `thứ 6`, `chủ nhật`, `ngày 5`, `ngày 5/10`. Cụm tìm được bị bỏ khỏi các từ còn lại.
/// Không bao giờ trả về thời điểm ở tương lai.
enum DateHint {
    struct Result: Equatable, Sendable {
        var tokens: [String]
        /// nil khi không có cụm chỉ ngày, hoặc khi đó là hôm nay (ghi theo giờ hiện tại).
        var date: Date?
    }

    /// Giờ mặc định của khoản ghi cho ngày đã qua khi không nói buổi nào.
    static let defaultHour = 12

    private static let periods: [(word: String, hour: Int)] = [
        ("sáng", 8), ("trưa", 12), ("chiều", 15), ("tối", 19), ("đêm", 22),
    ]
    private static let dayPhrases: [(phrase: [String], offset: Int)] = [
        (["hôm", "qua"], -1), (["hôm", "kia"], -2), (["hôm", "nay"], 0),
    ]
    private static let spokenDigits: [(word: String, value: Int)] = [
        ("một", 1), ("hai", 2), ("ba", 3), ("bốn", 4), ("tư", 4), ("năm", 5), ("sáu", 6), ("bảy", 7), ("tám", 8), ("chín", 9),
    ]

    static func extract(from tokens: [String], now: Date, calendar: Calendar) -> Result {
        let today = calendar.startOfDay(for: now)
        return relativeDay(tokens, today: today, now: now, calendar: calendar)
            ?? periodOfToday(tokens, today: today, now: now, calendar: calendar)
            ?? daysAgo(tokens, today: today, now: now, calendar: calendar)
            ?? weekday(tokens, today: today, now: now, calendar: calendar)
            ?? dayOfMonth(tokens, today: today, now: now, calendar: calendar)
            ?? Result(tokens: tokens, date: nil)
    }

    // MARK: - hôm qua, tối hôm qua, hôm kia

    private static func relativeDay(_ tokens: [String], today: Date, now: Date, calendar: Calendar) -> Result? {
        for (phrase, offset) in dayPhrases {
            guard let at = TextNormalizer.firstIndex(of: phrase, in: tokens) else { continue }
            var range = at..<(at + phrase.count)
            var hour: Int?
            if at > 0, let period = periodHour(tokens[at - 1]) {
                hour = period
                range = (at - 1)..<range.upperBound
            } else if range.upperBound < tokens.count, let period = periodHour(tokens[range.upperBound]) {
                hour = period
                range = range.lowerBound..<(range.upperBound + 1)
            }
            return result(removing: range, from: tokens, date: moment(daysBack: -offset, hour: hour, today: today, now: now, calendar: calendar))
        }
        return nil
    }

    // MARK: - sáng nay, tối qua

    private static func periodOfToday(_ tokens: [String], today: Date, now: Date, calendar: Calendar) -> Result? {
        for (word, hour) in periods {
            for (suffix, offset) in [("nay", 0), ("qua", -1)] {
                guard let at = TextNormalizer.firstIndex(of: [word, suffix], in: tokens) else { continue }
                return result(
                    removing: at..<(at + 2), from: tokens,
                    date: moment(daysBack: -offset, hour: hour, today: today, now: now, calendar: calendar)
                )
            }
        }
        return nil
    }

    // MARK: - 3 ngày trước

    private static func daysAgo(_ tokens: [String], today: Date, now: Date, calendar: Calendar) -> Result? {
        guard tokens.count >= 3 else { return nil }
        for index in 0...(tokens.count - 3) {
            guard TextNormalizer.matches(tokens[index + 1], "ngày"), TextNormalizer.matches(tokens[index + 2], "trước"),
                  let days = number(tokens[index]), (1...60).contains(days) else { continue }
            return result(
                removing: index..<(index + 3), from: tokens,
                date: moment(daysBack: days, hour: nil, today: today, now: now, calendar: calendar)
            )
        }
        return nil
    }

    // MARK: - thứ 6, chủ nhật

    private static func weekday(_ tokens: [String], today: Date, now: Date, calendar: Calendar) -> Result? {
        var found: (range: Range<Int>, weekday: Int)?
        if let at = TextNormalizer.firstIndex(of: ["chủ", "nhật"], in: tokens) {
            found = (at..<(at + 2), 1)
        } else if tokens.count >= 2 {
            for index in 0...(tokens.count - 2) where TextNormalizer.matches(tokens[index], "thứ") {
                let next = tokens[index + 1]
                if let value = number(next), (2...7).contains(value) {
                    found = (index..<(index + 2), value)
                    break
                }
            }
        }
        guard let found else { return nil }
        let todayWeekday = calendar.component(.weekday, from: today)
        let back = (todayWeekday - found.weekday + 7) % 7
        return result(
            removing: found.range, from: tokens,
            date: moment(daysBack: back, hour: nil, today: today, now: now, calendar: calendar)
        )
    }

    // MARK: - ngày 5, ngày 5/10

    private static func dayOfMonth(_ tokens: [String], today: Date, now: Date, calendar: Calendar) -> Result? {
        guard tokens.count >= 2 else { return nil }
        for index in 0...(tokens.count - 2) where TextNormalizer.matches(tokens[index], "ngày") {
            let parts = tokens[index + 1].split(separator: "/").map { Int($0) }
            var length = 2
            var day: Int?
            var month: Int?
            if parts.count == 2, let d = parts[0], let m = parts[1] {
                day = d
                month = m
            } else if parts.count == 1, let d = parts[0] {
                day = d
                if index + 3 < tokens.count, TextNormalizer.matches(tokens[index + 2], "tháng"), let m = Int(tokens[index + 3]) {
                    month = m
                    length = 4
                }
            }
            guard let day, (1...31).contains(day) else { continue }
            guard let date = resolve(day: day, month: month, today: today, now: now, calendar: calendar) else { continue }
            return result(removing: index..<(index + length), from: tokens, date: date)
        }
        return nil
    }

    /// Ngày gần nhất không ở tương lai. Không có tháng thì lấy tháng này, hoặc tháng trước nếu ngày đó chưa tới.
    private static func resolve(day: Int, month: Int?, today: Date, now: Date, calendar: Calendar) -> Date? {
        let current = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = current.year, let currentMonth = current.month, let currentDay = current.day else { return nil }
        func make(_ year: Int, _ month: Int) -> Date? {
            guard (1...12).contains(month),
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: defaultHour)),
                  calendar.component(.day, from: date) == day else { return nil }   // 31/9 không tồn tại
            return date
        }
        if let month {
            if let date = make(year, month), date <= now { return date }
            return make(year - 1, month)
        }
        if day <= currentDay { return make(year, currentMonth) }
        return currentMonth == 1 ? make(year - 1, 12) : make(year, currentMonth - 1)
    }

    // MARK: - Dùng chung

    private static func periodHour(_ token: String) -> Int? {
        periods.first { TextNormalizer.matches(token, $0.word) }?.hour
    }

    /// Số viết bằng chữ số hoặc chữ (một đến chín).
    private static func number(_ token: String) -> Int? {
        if let value = Int(token), token.allSatisfy({ $0.isASCII && $0.isNumber }) { return value }
        return spokenDigits.first { TextNormalizer.matches(token, $0.word) }?.value
    }

    /// Lùi `daysBack` ngày, đặt giờ `hour` (mặc định 12 giờ cho ngày đã qua). Hôm nay không nói giờ thì nil.
    private static func moment(daysBack: Int, hour: Int?, today: Date, now: Date, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return nil }
        guard let hour = hour ?? (daysBack == 0 ? nil : defaultHour),
              let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
        return min(date, now)
    }

    private static func result(removing range: Range<Int>, from tokens: [String], date: Date?) -> Result {
        var tokens = tokens
        tokens.removeSubrange(range)
        return Result(tokens: tokens, date: date)
    }
}
