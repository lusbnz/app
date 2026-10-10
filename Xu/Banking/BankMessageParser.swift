import Foundation

/// Một giao dịch đọc ra từ tin nhắn của ngân hàng hoặc ví điện tử.
struct BankTransaction: Equatable, Sendable {
    enum Direction: Sendable {
        /// Tiền ra: chi tiêu, chuyển đi.
        case debit
        /// Tiền vào: nhận tiền, hoàn tiền.
        case credit
    }

    var direction: Direction
    /// Số tiền, đơn vị đồng, luôn dương.
    var amount: Int
    var balanceAfter: Int?
    /// Nội dung hoặc nơi nhận, đã làm gọn ("Highlands Coffee").
    var description: String?
    /// Vài số cuối của tài khoản, nếu tin nhắn có.
    var accountSuffix: String?
    /// Lúc giao dịch ghi trong tin nhắn, nếu đọc được và không ở tương lai.
    var date: Date?
}

/// Đọc tin nhắn ngân hàng và ví điện tử của Việt Nam: "TK 0011 -450,000VND luc 10/10/2026 14:22. SD 12,345,678VND. ND: ...",
/// "Bạn đã thanh toán thành công 45.000đ cho Highlands Coffee", "+1,000,000 VND ... So du 5,000,000 VND".
/// Không chắc là tiền vào hay tiền ra thì trả về nil, để không ghi sai.
enum BankMessageParser {
    private struct MoneyMatch {
        var value: Int
        var sign: Character?
        var hasMarker: Bool
        var isBalance: Bool
        var range: Range<String.Index>
    }

    static func parse(_ message: String, now: Date, calendar: Calendar) -> BankTransaction? {
        let original = message.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r", with: "\n")
        let folded = foldCharacterwise(original)
        guard !folded.isEmpty else { return nil }

        let money = moneyMatches(in: folded)
        guard let primary = money.first(where: { !$0.isBalance && ($0.sign != nil || $0.hasMarker) }) else { return nil }
        guard let direction = direction(of: primary, in: folded) else { return nil }
        let balance = money.first(where: \.isBalance)?.value
        return BankTransaction(
            direction: direction,
            amount: primary.value,
            balanceAfter: balance,
            description: description(in: folded, original: original, direction: direction),
            accountSuffix: accountSuffix(in: folded),
            date: date(in: folded, now: now, calendar: calendar)
        )
    }

    // MARK: - Chữ

    /// Bỏ dấu và hạ chữ thường từng ký tự một, giữ nguyên số ký tự để vị trí trong bản gốc và bản đã bỏ dấu khớp nhau.
    /// Ký tự nào bỏ dấu ra khác một ký tự thì giữ nguyên dạng chữ thường.
    private static func foldCharacterwise(_ text: String) -> String {
        String(text.map { character -> Character in
            let folded = TextNormalizer.fold(String(character))
            return folded.count == 1 ? folded[folded.startIndex] : Character(String(character).lowercased())
        })
    }

    // MARK: - Số tiền

    private static let moneyPattern = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.,])([+\-−–])?\s?(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s?(vnd|vnđ|d|₫)?(?![\p{L}\p{N}])"#,
        options: []
    )

    private static func moneyMatches(in folded: String) -> [MoneyMatch] {
        guard let regex = moneyPattern else { return [] }
        let range = NSRange(folded.startIndex..., in: folded)
        var result: [MoneyMatch] = []
        // Một số là số dư khi từ "số dư" nằm giữa số tiền liền trước (nếu có) và nó. Số trần như số tài khoản
        // không tính là số tiền nên không làm mốc.
        var boundary = folded.startIndex
        for match in regex.matches(in: folded, range: range) {
            guard let whole = Range(match.range, in: folded), let digits = Range(match.range(at: 2), in: folded),
                  let value = vndValue(String(folded[digits])), value >= 1 else { continue }
            let sign = Range(match.range(at: 1), in: folded).flatMap { folded[$0].first }
            let hasMarker = Range(match.range(at: 3), in: folded) != nil
            let isMoney = sign != nil || hasMarker
            result.append(MoneyMatch(
                value: value, sign: sign.map(normalizedSign), hasMarker: hasMarker,
                isBalance: isMoney && isBalance(in: folded[boundary..<whole.lowerBound]), range: whole
            ))
            if isMoney { boundary = whole.upperBound }
        }
        return result
    }

    private static func normalizedSign(_ sign: Character) -> Character {
        sign == "+" ? "+" : "-"
    }

    /// "450,000" "450.000" "450,000.00" "450000" thành đồng; phần lẻ (nếu có) bỏ đi.
    static func vndValue(_ text: String) -> Int? {
        let parts = text.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }.map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        var whole = parts
        // Nhóm cuối có 1 đến 2 chữ số sau dấu ngăn cách là phần lẻ, không phải nhóm nghìn.
        if parts.count > 1, let last = parts.last, last.count <= 2 { whole.removeLast() }
        // Nhóm đầu tối đa 3 chữ số (hoặc là số trần không có dấu ngăn cách), các nhóm sau đúng 3 chữ số.
        guard let first = whole.first, whole.count == 1 || (first.count <= 3 && whole.dropFirst().allSatisfy { $0.count == 3 }) else {
            return nil
        }
        return Int(whole.joined())
    }

    /// Số đứng sau chữ "số dư" (SD, so du, balance, còn lại) là số dư chứ không phải số tiền giao dịch.
    /// `gap` là đoạn chữ từ số tiền liền trước tới số này; chỉ xét phần cuối vì từ khóa luôn đứng gần.
    private static func isBalance(in gap: Substring) -> Bool {
        let window = String(gap.suffix(30))
        return ["so du", "sodu", "balance", "con lai"].contains { window.contains($0) }
            || window.contains("sd:") || window.contains("sd ") || window.hasSuffix("sd")
    }

    // MARK: - Tiền vào hay tiền ra

    private static let creditWords = ["nhan duoc", "da nhan", "nhan tien", "tien vao", "ghi co", "cong tien", "nap tien", "hoan tien", "luong", "nhan ", "credit"]
    private static let debitWords = ["thanh toan", "da chuyen", "chuyen tien", "chuyen khoan", "rut tien", "ghi no", "tru tien", "da tra", "mua", "payment", "debit", "tru "]

    private static func direction(of primary: MoneyMatch, in folded: String) -> BankTransaction.Direction? {
        if let sign = primary.sign { return sign == "+" ? .credit : .debit }
        // Không có dấu thì dựa vào từ khóa ở trước số tiền (gần nhất thắng).
        let before = String(folded[..<primary.range.lowerBound])
        let credit = creditWords.compactMap { lastIndex(of: $0, in: before) }.max()
        let debit = debitWords.compactMap { lastIndex(of: $0, in: before) }.max()
        switch (credit, debit) {
        case (nil, nil): return nil
        case (.some, nil): return .credit
        case (nil, .some): return .debit
        case let (.some(c), .some(d)): return c > d ? .credit : .debit
        }
    }

    private static func lastIndex(of word: String, in text: String) -> Int? {
        guard let range = text.range(of: word, options: .backwards) else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    // MARK: - Nội dung

    private static let contentPattern = try? NSRegularExpression(
        pattern: #"(?:nd|noi dung(?: gd| giao dich)?|dien giai|content)\s*[:：]\s*([^\n]+)"#
    )
    private static let debitPartyPattern = try? NSRegularExpression(
        pattern: #"(?:^|\s)(?:tai|cho|toi|den)\s+([^\n.,;]+)"#
    )
    private static let creditPartyPattern = try? NSRegularExpression(
        pattern: #"(?:^|\s)(?:tu|boi)\s+([^\n.,;]+)"#
    )
    /// Phần đuôi không thuộc nội dung: số dư, mã tham chiếu, lời cảm ơn.
    private static let cutWords = [" so du", " sd ", " sd:", " ref", " ma gd", " ma giao dich", " cam on", " thanks", " balance"]

    private static func description(in folded: String, original: String, direction: BankTransaction.Direction) -> String? {
        let patterns = [contentPattern, direction == .debit ? debitPartyPattern : creditPartyPattern]
        for pattern in patterns {
            guard let pattern, let match = pattern.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
                  let capture = Range(match.range(at: 1), in: folded) else { continue }
            var end = capture.upperBound
            let captured = String(folded[capture])
            for cut in cutWords {
                if let found = captured.range(of: cut) {
                    let candidate = folded.index(capture.lowerBound, offsetBy: captured.distance(from: captured.startIndex, to: found.lowerBound))
                    if candidate < end { end = candidate }
                }
            }
            // Lấy lại chữ gốc (có dấu, hoa thường) ở đúng vị trí.
            let startOffset = folded.distance(from: folded.startIndex, to: capture.lowerBound)
            let endOffset = folded.distance(from: folded.startIndex, to: end)
            guard original.count == folded.count else { continue }
            let from = original.index(original.startIndex, offsetBy: startOffset)
            let to = original.index(original.startIndex, offsetBy: endOffset)
            if let cleaned = clean(String(original[from..<to])) { return cleaned }
        }
        return nil
    }

    private static func clean(_ text: String) -> String? {
        var result = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-–|"))
        guard result.contains(where: \.isLetter) else { return nil }
        // Tin nhắn ngân hàng hay viết hoa toàn bộ; đưa về dạng viết hoa chữ cái đầu mỗi từ cho dễ đọc.
        if result == result.uppercased() { result = result.capitalized }
        return String(result.prefix(60))
    }

    // MARK: - Tài khoản

    private static let accountPattern = try? NSRegularExpression(pattern: #"(?:tk|tai khoan|account|a/c|stk)\s*(?:so\s*)?[:.]?\s*([0-9x*]{4,})"#)

    private static func accountSuffix(in folded: String) -> String? {
        guard let accountPattern, let match = accountPattern.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let capture = Range(match.range(at: 1), in: folded) else { return nil }
        let digits = folded[capture].filter(\.isNumber)
        return digits.count >= 4 ? String(digits.suffix(4)) : nil
    }

    // MARK: - Ngày giờ

    private static let datePattern = try? NSRegularExpression(
        pattern: #"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})(?:[^\d]{1,6}(\d{1,2}):(\d{2})(?::(\d{2}))?)?"#
    )
    private static let timeFirstPattern = try? NSRegularExpression(
        pattern: #"(\d{1,2}):(\d{2})(?::(\d{2}))?[^\d]{1,6}(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})"#
    )

    private static func date(in folded: String, now: Date, calendar: Calendar) -> Date? {
        let range = NSRange(folded.startIndex..., in: folded)
        func number(_ match: NSTextCheckingResult, _ group: Int) -> Int? {
            Range(match.range(at: group), in: folded).flatMap { Int(folded[$0]) }
        }
        var parts: (day: Int, month: Int, year: Int, hour: Int, minute: Int)?
        if let match = timeFirstPattern?.firstMatch(in: folded, range: range),
           let hour = number(match, 1), let minute = number(match, 2),
           let day = number(match, 4), let month = number(match, 5), let year = number(match, 6) {
            parts = (day, month, year, hour, minute)
        } else if let match = datePattern?.firstMatch(in: folded, range: range),
                  let day = number(match, 1), let month = number(match, 2), let year = number(match, 3) {
            parts = (day, month, year, number(match, 4) ?? 12, number(match, 5) ?? 0)
        }
        guard let parts, (1...31).contains(parts.day), (1...12).contains(parts.month), (0...23).contains(parts.hour),
              (0...59).contains(parts.minute) else { return nil }
        let year = parts.year < 100 ? 2000 + parts.year : parts.year
        let components = DateComponents(year: year, month: parts.month, day: parts.day, hour: parts.hour, minute: parts.minute)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts.day,          // 31/2 không có thật
              date <= now.addingTimeInterval(600) else { return nil }
        return date
    }
}
