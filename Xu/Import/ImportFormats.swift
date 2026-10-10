import Foundation

/// Đọc ngày giờ trong tệp nhập. Ngày đứng trước tháng ("5/10/2026" là 5 tháng 10), trừ khi năm đứng đầu ("2026-10-05").
enum ImportDate {
    /// Giờ mặc định cho dòng chỉ có ngày.
    static let defaultHour = 12

    /// "2026-10-05", "2026-10-05 14:30", "2026-10-05T14:30:00", "05/10/2026", "5-10-26 2:30 PM". Nil khi không phải ngày thật (31/02).
    static func parse(_ text: String, time: String? = nil, calendar: Calendar) -> Date? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "T" || $0 == "\u{A0}" }).map(String.init)
        guard let datePart = tokens.first else { return nil }
        let numbers = datePart.split(whereSeparator: { "/-.".contains($0) }).map(String.init)
        guard numbers.count == 3, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let first = Int(numbers[0]), let second = Int(numbers[1]), let third = Int(numbers[2]) else { return nil }

        let year: Int, month: Int, day: Int
        if numbers[0].count == 4 {
            (year, month, day) = (first, second, third)
        } else if numbers[2].count == 4 {
            (year, month, day) = (third, second, first)
        } else if numbers[2].count == 2 {
            (year, month, day) = (2000 + third, second, first)
        } else {
            return nil
        }

        let clock = clockTime(tokens.dropFirst().joined(separator: " ")) ?? time.flatMap(clockTime)
        return makeDate(year: year, month: month, day: day, hour: clock?.hour ?? defaultHour, minute: clock?.minute ?? 0, calendar: calendar)
    }

    /// "14:30", "14:30:15", "2:30 PM", "2:30 CH". Nil khi không đọc được.
    static func clockTime(_ text: String) -> (hour: Int, minute: Int)? {
        let tokens = text.split(separator: " ").map(String.init)
        guard let clock = tokens.first else { return nil }
        let digits = clock.prefix { $0.isASCII && ($0.isNumber || $0 == ":") }
        let parts = digits.split(separator: ":").map(String.init)
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        let marker = (tokens.dropFirst().first ?? String(clock.dropFirst(digits.count))).lowercased()
        if ["pm", "ch"].contains(marker), hour < 12 { return (hour + 12, minute) }
        if ["am", "sa"].contains(marker), hour == 12 { return (0, minute) }
        return (hour, minute)
    }

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else { return nil }
        // Calendar tự dồn 31/02 sang tháng 3; ngày như vậy là sai nên bỏ.
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day ? date : nil
    }
}

/// Đọc số tiền trong tệp nhập, ra đơn vị đồng.
enum ImportAmount {
    struct Value: Equatable, Sendable {
        var dong: Int
        var isNegative: Bool
    }

    /// "45000", "45.000", "45,000đ", "1.234.567,50", "-45.000", "(45.000)", "45 000 VND". Nil khi không có số hoặc số là 0.
    /// Dấu `.` hoặc `,` theo sau bởi đúng ba chữ số là dấu nghìn; theo sau bởi một hoặc hai chữ số là phần lẻ (bỏ đi, vì tiền lưu theo đồng).
    static func parse(_ text: String) -> Value? {
        var negative = text.contains("(") && text.contains(")")
        var body = ""
        for character in text {
            if character == "-" || character == "\u{2212}" {
                negative = true
            } else if (character.isASCII && character.isNumber) || character == "." || character == "," {
                body.append(character)
            }
        }
        guard body.contains(where: { $0.isNumber }) else { return nil }

        var integer = body
        let hasDot = body.contains("."), hasComma = body.contains(",")
        if hasDot && hasComma {
            if let last = body.lastIndex(where: { $0 == "." || $0 == "," }), body[body.index(after: last)...].count <= 2 {
                integer = String(body[..<last])
            }
        } else if hasDot || hasComma {
            let separator: Character = hasDot ? "." : ","
            let groups = body.split(separator: separator, omittingEmptySubsequences: false)
            if groups.count == 2, groups[1].count != 3 { integer = String(groups[0]) }
        }
        guard let dong = Int(integer.filter(\.isNumber)), dong > 0 else { return nil }
        return Value(dong: dong, isNegative: negative)
    }
}
