import Foundation

/// Nhận ra số tiền ngoại tệ trong một khoản đã tách thành từ: `20usd`, `$20`, `20 $`, `usd 20`,
/// `5 euro`, `12,5 eur`, `10k yên`, `20 đô la`. Không có tên hay ký hiệu tiền thì không nhận
/// (`45k` vẫn là tiền đồng).
enum ForeignAmountParser {
    struct Match: Equatable, Sendable {
        var range: Range<Int>
        var amount: ForeignAmount
    }

    private static let multipliers: [(words: [String], factor: Int)] = [
        (["k", "nghìn", "ngàn"], 1_000), (["tr", "triệu", "m"], 1_000_000),
    ]

    static func find(in tokens: [String]) -> Match? {
        var found: Match?
        var index = 0
        while index < tokens.count {
            if let match = match(at: index, in: tokens) {
                found = match
                index = match.range.upperBound
            } else {
                index += 1
            }
        }
        return found
    }

    // MARK: - Một vị trí

    private static func match(at index: Int, in tokens: [String]) -> Match? {
        let token = TextNormalizer.lowercased(tokens[index])

        // "usd 20", "$ 20": tên hoặc ký hiệu tiền đứng riêng, số ở từ sau.
        if let currency = currency(ofWord: token) ?? symbolOnly(token), index + 1 < tokens.count,
           let number = number(tokens[index + 1]), number.suffix.isEmpty || multiplier(number.suffix) != nil {
            return build(currency: currency, number: number, range: index..<index + 2)
        }

        guard let number = number(token) else { return nil }
        // "$20", "usd20", "20$", "20usd", "10kyen": ký hiệu hoặc tên dính vào số.
        if let currency = number.currency {
            return build(currency: currency, number: number, range: index..<index + 1)
        }
        // "20 usd", "10k yên", "20 đô la": tên tiền ở từ sau.
        if number.suffix.isEmpty || multiplier(number.suffix) != nil, index + 1 < tokens.count {
            let next = TextNormalizer.lowercased(tokens[index + 1])
            if let currency = currency(ofWord: next) ?? symbolOnly(next) {
                var end = index + 2
                if currency == .usd, TextNormalizer.matches(next, "đô"), end < tokens.count,
                   TextNormalizer.matches(tokens[end], "la") {
                    end += 1
                }
                return build(currency: currency, number: number, range: index..<end)
            }
        }
        return nil
    }

    private static func build(currency: Currency, number: Number, range: Range<Int>) -> Match? {
        let factor = multiplier(number.suffix) ?? 1
        guard let minor = minorUnits(of: number.digits, currency: currency, factor: factor) else { return nil }
        return Match(range: range, amount: ForeignAmount(currency: currency, minor: minor))
    }

    // MARK: - Đọc một từ

    private struct Number {
        var currency: Currency?
        var digits: String
        /// Chữ dính sau số: `k`, `tr`; nếu là tên tiền thì đã chuyển vào `currency`.
        var suffix: String
    }

    private static func number(_ rawToken: String) -> Number? {
        var rest = Substring(TextNormalizer.lowercased(rawToken))
        var currency: Currency?
        for (symbol, candidate) in Currency.symbols where rest.hasPrefix(symbol) {
            currency = candidate
            rest = rest.dropFirst(symbol.count)
            break
        }
        if currency == nil, let named = leadingWord(of: rest) {
            currency = named.currency
            rest = rest.dropFirst(named.length)
        }
        var digits = ""
        while let first = rest.first, first.isASCII, first.isNumber || ((first == "." || first == ",") && !digits.isEmpty) {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard let last = digits.last, last.isNumber else { return nil }

        var suffix = String(rest)
        if currency == nil {
            for (symbol, candidate) in Currency.symbols where suffix.hasPrefix(symbol) && suffix == symbol {
                currency = candidate
                suffix = ""
                break
            }
        }
        if currency == nil, let named = Currency.allCases.first(where: { $0.words.contains(suffix) }) {
            currency = named
            suffix = ""
        } else if currency == nil, let split = splitMultiplier(suffix) {
            // "10kyên": hệ số rồi tên tiền.
            currency = split.currency
            suffix = split.multiplier
        }
        guard suffix.isEmpty || multiplier(suffix) != nil else { return nil }
        return Number(currency: currency, digits: digits, suffix: suffix)
    }

    private static func leadingWord(of text: Substring) -> (currency: Currency, length: Int)? {
        var best: (Currency, Int)?
        for currency in Currency.allCases {
            for word in currency.words where text.hasPrefix(word) && word.count >= 3 {
                let next = text.dropFirst(word.count).first
                // Tên tiền đứng đầu từ phải liền với số ("usd20"), tránh nuốt chữ thường như "dollar".
                guard next?.isNumber == true, word.count > (best?.1 ?? 0) else { continue }
                best = (currency, word.count)
            }
        }
        return best
    }

    private static func splitMultiplier(_ suffix: String) -> (multiplier: String, currency: Currency)? {
        for entry in multipliers {
            for word in entry.words where suffix.hasPrefix(word) {
                let tail = String(suffix.dropFirst(word.count))
                if let currency = Currency.allCases.first(where: { $0.words.contains(tail) }) {
                    return (word, currency)
                }
            }
        }
        return nil
    }

    private static func currency(ofWord word: String) -> Currency? {
        Currency.allCases.first { $0.words.contains(word) }
    }

    private static func symbolOnly(_ word: String) -> Currency? {
        Currency.symbols.first { $0.symbol == word }?.currency
    }

    private static func multiplier(_ suffix: String) -> Int? {
        guard !suffix.isEmpty else { return nil }
        return multipliers.first { $0.words.contains(suffix) }?.factor
    }

    // MARK: - Đọc số

    /// `1,234.56` và `1.234,56` đều là một nghìn hai trăm ba mươi tư phẩy năm mươi sáu. Một dấu duy nhất
    /// kèm đúng ba chữ số là dấu ngăn cách nghìn (`1.000`), còn lại là dấu thập phân.
    static func minorUnits(of text: String, currency: Currency, factor: Int = 1) -> Int? {
        let separators = text.filter { $0 == "." || $0 == "," }
        var whole = text
        var fraction = ""
        if let lastIndex = text.lastIndex(where: { $0 == "." || $0 == "," }) {
            let head = String(text[..<lastIndex])
            let tail = String(text[text.index(after: lastIndex)...])
            let isGrouping: Bool
            if separators.count == 1 {
                isGrouping = tail.count == 3 && head != "0"
            } else {
                isGrouping = Set(separators).count == 1       // 1.000.000
            }
            if isGrouping {
                whole = text.filter { $0 != "." && $0 != "," }
            } else {
                whole = head.filter { $0 != "." && $0 != "," }
                fraction = tail
            }
        }
        guard !whole.isEmpty, let wholeValue = Int(whole), wholeValue < 1_000_000_000 else { return nil }
        var digits = fraction
        if digits.count > currency.minorDigits { digits = String(digits.prefix(currency.minorDigits)) }
        digits += String(repeating: "0", count: currency.minorDigits - digits.count)
        var scale = 1
        for _ in 0..<currency.minorDigits { scale *= 10 }
        let minor = wholeValue * scale + (Int(digits) ?? 0)
        let scaled = minor * factor
        return scaled > 0 ? scaled : nil
    }
}
