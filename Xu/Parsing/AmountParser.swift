import Foundation

/// Đọc số tiền kiểu người Việt hay gõ: `45k`, `45k5`, `45k rưỡi`, `1tr2`, `1 củ 2`, `1,5tr`, `45.000`, `5 lít`.
enum AmountParser {
    struct Match: Equatable, Sendable {
        var range: Range<Int>
        var value: Int
        var hasUnit: Bool
    }

    private static let units: [(words: [String], multiplier: Int)] = [
        (["k", "nghìn", "ngàn"], 1_000),
        (["tr", "triệu", "củ"], 1_000_000),
        (["lít", "xị"], 100_000),
        (["đ", "vnd", "vnđ", "đồng"], 1),
    ]

    private static let maxWhole = 1_000_000_000

    static func multiplier(forUnit unit: String) -> Int? {
        units.first { $0.words.contains { TextNormalizer.matches(unit, $0) } }?.multiplier
    }

    /// Tìm số tiền trong một khoản đã tách thành từ. Ưu tiên số có đơn vị,
    /// sau đó là số trần ở cuối, rồi số trần ở đầu.
    static func find(in tokens: [String]) -> Match? {
        var matches: [Match] = []
        var index = 0
        while index < tokens.count {
            guard let scanned = scan(tokens[index]) else {
                index += 1
                continue
            }
            if !scanned.unit.isEmpty {
                if let multiplier = multiplier(forUnit: scanned.unit),
                   let value = value(of: scanned, multiplier: multiplier) {
                    let (extra, length) = suffix(in: tokens, after: index + 1, scanned: scanned, multiplier: multiplier)
                    matches.append(Match(range: index..<index + 1 + length, value: value + extra, hasUnit: true))
                    index += length
                }
                index += 1
            } else if index + 1 < tokens.count,
                      let multiplier = multiplier(forUnit: tokens[index + 1]),
                      let value = value(of: scanned, multiplier: multiplier) {
                let (extra, length) = suffix(in: tokens, after: index + 2, scanned: scanned, multiplier: multiplier)
                matches.append(Match(range: index..<index + 2 + length, value: value + extra, hasUnit: true))
                index += 2 + length
            } else {
                if let value = value(of: scanned, multiplier: nil) {
                    matches.append(Match(range: index..<index + 1, value: value, hasUnit: false))
                }
                index += 1
            }
        }
        if let withUnit = matches.last(where: \.hasUnit) { return withUnit }
        if let last = matches.last, last.range.upperBound == tokens.count { return last }
        if let first = matches.first, first.range.lowerBound == 0 { return first }
        return matches.last
    }

    /// Một từ đứng riêng có phải số tiền không, ví dụ `460k`.
    static func isAmount(_ token: String) -> Bool {
        find(in: [token]) != nil
    }

    /// Đọc một ô chỉ chứa số tiền, ví dụ `45k` hay `1 củ`.
    static func amount(from text: String) -> Int? {
        find(in: TextNormalizer.words(text))?.value
    }


    /// Từ đếm đứng sau số: `1 triệu 2 cái` thì `2` là số lượng, không phải số lẻ của tiền.
    private static let counters = ["cái", "ly", "phần", "chai", "lon", "bát", "tô", "hộp", "lần", "ngày", "tháng", "người", "kg", "g"]

    /// Phần đọc thêm sau đơn vị: `45k rưỡi`, `1 triệu rưỡi` (thêm nửa đơn vị),
    /// `1 củ 2`, `1 triệu 250` (số lẻ của triệu). Trả về số tiền thêm và số từ đã dùng.
    private static func suffix(in tokens: [String], after start: Int, scanned: Scanned, multiplier: Int) -> (extra: Int, length: Int) {
        guard multiplier > 1, scanned.tail.isEmpty, scanned.number.allSatisfy(\.isNumber), start < tokens.count else {
            return (0, 0)
        }
        let next = tokens[start]
        if TextNormalizer.matches(next, "rưỡi") {
            return (multiplier / 2, 1)
        }
        guard multiplier >= 1_000_000, (1...3).contains(next.count), next.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return (0, 0)
        }
        if start + 1 < tokens.count, counters.contains(where: { TextNormalizer.matches(tokens[start + 1], $0) }) {
            return (0, 0)
        }
        return (scaled(whole: 0, decimals: next, by: multiplier), 1)
    }

    // MARK: - Đọc một từ

    private struct Scanned {
        var number: String
        var unit: String
        var tail: String
    }

    /// Tách một từ thành ba phần: số, đơn vị, số lẻ theo sau (`45` `k` `5`).
    private static func scan(_ token: String) -> Scanned? {
        let characters = Array(TextNormalizer.lowercased(token))
        var index = 0
        var number = ""
        while index < characters.count {
            let character = characters[index]
            let isDigit = character.isASCII && character.isNumber
            let isSeparator = (character == "." || character == ",") && !number.isEmpty
            guard isDigit || isSeparator else { break }
            number.append(character)
            index += 1
        }
        guard let last = number.last, last.isNumber else { return nil }

        var unit = ""
        while index < characters.count, characters[index].isLetter {
            unit.append(characters[index])
            index += 1
        }
        var tail = ""
        while index < characters.count, characters[index].isASCII, characters[index].isNumber {
            tail.append(characters[index])
            index += 1
        }
        guard index == characters.count, unit.isEmpty ? tail.isEmpty : true else { return nil }
        return Scanned(number: number, unit: unit, tail: tail)
    }

    private static func value(of scanned: Scanned, multiplier: Int?) -> Int? {
        let groups = scanned.number
            .split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
            .map(String.init)
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }

        let scales = (multiplier ?? 1) > 1
        var wholeDigits = groups[0]
        var decimals = ""
        if groups.count == 2, scales {
            decimals = groups[1]                       // 1,5tr
        } else if groups.count > 1, groups.dropFirst().allSatisfy({ $0.count == 3 }) {
            wholeDigits = groups.joined()              // 45.000
        } else if groups.count == 2 {
            decimals = groups[1]                       // 1,5 không đơn vị, hiểu là nghìn
        } else if groups.count > 2 {
            return nil
        }
        if !scanned.tail.isEmpty {
            guard decimals.isEmpty, scales else { return nil }
            decimals = scanned.tail                    // 45k5, 1tr2
        }
        guard let whole = Int(wholeDigits), whole <= maxWhole, decimals.count <= 6 else { return nil }

        let result: Int
        if scales, let multiplier {
            result = scaled(whole: whole, decimals: decimals, by: multiplier)
        } else if !decimals.isEmpty {
            result = scaled(whole: whole, decimals: decimals, by: 1_000)
        } else {
            result = whole < 1_000 ? whole * 1_000 : whole
        }
        return result > 0 ? result : nil
    }

    private static func scaled(whole: Int, decimals: String, by multiplier: Int) -> Int {
        guard let fraction = Int(decimals) else { return whole * multiplier }
        var divisor = 1
        for _ in 0..<decimals.count { divisor *= 10 }
        return whole * multiplier + fraction * multiplier / divisor
    }
}
