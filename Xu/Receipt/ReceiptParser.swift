import Foundation

/// Những gì đọc được từ một hóa đơn.
struct ReceiptReading: Equatable, Sendable {
    var merchant: String
    var total: Int?
    var date: Date?
}

/// Luật tìm tổng tiền, ngày giờ và tên cửa hàng trong các dòng chữ đã nhận dạng. Không tách từng món.
enum ReceiptParser {
    static func parse(lines: [String], now: Date, calendar: Calendar) -> ReceiptReading {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ReceiptReading(
            merchant: merchant(in: lines),
            total: total(in: lines),
            date: date(in: lines, now: now, calendar: calendar)
        )
    }

    // MARK: - Tên cửa hàng

    /// Dòng đầu tiên có chữ.
    static func merchant(in lines: [String]) -> String {
        lines.first { $0.filter(\.isLetter).count >= 2 } ?? ""
    }

    // MARK: - Tổng tiền

    /// Từ khóa theo thứ tự ưu tiên: số thực trả đứng trước tổng chưa giảm.
    private static let totalKeywords = ["thanh toan", "tong cong", "tong tien", "thanh tien", "total", "tong"]
    private static let subtotalKeywords = ["subtotal", "sub total", "tam tinh"]

    static func total(in lines: [String]) -> Int? {
        let folded = lines.map(TextNormalizer.keyword)
        for keyword in totalKeywords {
            var found: [Int] = []
            for (index, line) in folded.enumerated() where line.contains(keyword) {
                guard !subtotalKeywords.contains(where: line.contains) else { continue }
                var amounts = amounts(in: lines[index])
                // Nhãn và số tiền có khi bị nhận dạng thành hai dòng.
                if amounts.isEmpty, index + 1 < lines.count, isOnlyAmount(lines[index + 1]) {
                    amounts = Self.amounts(in: lines[index + 1])
                }
                found.append(contentsOf: amounts)
            }
            if let largest = found.max() { return largest }
        }
        return lines.flatMap(amounts).max()
    }

    private static func isOnlyAmount(_ line: String) -> Bool {
        let rest = TextNormalizer.fold(line)
            .filter { !$0.isNumber && !$0.isWhitespace && !".,".contains($0) }
        return ["", "d", "vnd", "dong"].contains(rest)
    }

    /// Các số tiền từ 1.000đ trong một dòng. Bỏ qua ngày, giờ, số điện thoại, mã số.
    static func amounts(in line: String) -> [Int] {
        let characters = Array(line)
        var amounts: [Int] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isASCII, characters[index].isNumber else {
                index += 1
                continue
            }
            let start = index
            while index < characters.count {
                let character = characters[index]
                let isDigit = character.isASCII && character.isNumber
                let isSeparator = (character == "." || character == ",")
                    && index + 1 < characters.count && characters[index + 1].isASCII && characters[index + 1].isNumber
                guard isDigit || isSeparator else { break }
                index += 1
            }
            let before = start > 0 ? characters[start - 1] : " "
            let after = index < characters.count ? characters[index] : " "
            guard !"/:-".contains(before), !"/:-".contains(after), !before.isLetter else { continue }
            if var value = value(of: String(characters[start..<index])) {
                if after == "k" || after == "K" { value *= 1_000 }
                if value >= 1_000 { amounts.append(value) }
            }
        }
        return amounts
    }

    private static func value(of token: String) -> Int? {
        var groups = token.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }.map(String.init)
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }
        if groups.count == 1 {
            // Dãy số dài không có dấu ngăn là số điện thoại hoặc mã số.
            return groups[0].count <= 7 ? Int(groups[0]) : nil
        }
        if let last = groups.last, last.count < 3 { groups.removeLast() }   // phần lẻ: 125.000,00
        guard groups.dropFirst().allSatisfy({ $0.count == 3 }), groups[0].count <= 3 else { return nil }
        let digits = groups.joined()
        return digits.count <= 12 ? Int(digits) : nil
    }

    // MARK: - Ngày giờ

    static func date(in lines: [String], now: Date, calendar: Calendar) -> Date? {
        var day: (year: Int, month: Int, day: Int, line: Int)?
        for (index, line) in lines.enumerated() {
            if let iso = firstMatch(#"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)"#, in: line) {
                day = (iso[0], iso[1], iso[2], index)
            } else if let local = firstMatch(#"(?<![\d.,])(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?![\d.,])"#, in: line) {
                day = (local[2] < 100 ? 2_000 + local[2] : local[2], local[1], local[0], index)
            }
            if day != nil { break }
        }
        guard let day, (1...12).contains(day.month), (1...31).contains(day.day) else { return nil }

        let timePattern = #"(?<![\d:])(\d{1,2}):(\d{2})(?!\d)"#
        let time = firstMatch(timePattern, in: lines[day.line])
            ?? lines.lazy.compactMap { firstMatch(timePattern, in: $0) }.first
        var parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12, minute: 0)
        if let time, (0...23).contains(time[0]), (0...59).contains(time[1]) {
            parts.hour = time[0]
            parts.minute = time[1]
        }
        guard let date = calendar.date(from: parts),
              calendar.component(.day, from: date) == day.day,
              let earliest = calendar.date(byAdding: .year, value: -1, to: now),
              let latest = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              date >= earliest, date < latest else { return nil }
        return date
    }

    /// Các nhóm số của lần khớp đầu tiên.
    private static func firstMatch(_ pattern: String, in line: String) -> [Int]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        let numbers = (1..<match.numberOfRanges).compactMap { group in
            Range(match.range(at: group), in: line).flatMap { Int(line[$0]) }
        }
        return numbers.count == match.numberOfRanges - 1 ? numbers : nil
    }
}
