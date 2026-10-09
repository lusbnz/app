import Foundation

enum ParsedLine: Equatable, Sendable {
    case expense(ParsedExpense)
    case loan(person: String, amount: Int)
    case question(String)
}

struct ParsedExpense: Equatable, Sendable {
    var name: String
    var amount: Int?            // phần của người dùng; nil nếu không đọc được
    var categoryKey: String
    var originalAmount: Int?
    var splitCount: Int?
    var isOutsideBudget: Bool
}

protocol LineParsing: Sendable {
    func parse(_ text: String, rules: [String: String], dailyAllowance: Int) -> [ParsedLine]
}

/// Bộ tách bằng luật, chạy trên máy.
struct ExpenseParser: LineParsing {
    /// Khoản lớn hơn bấy nhiêu lần hạn mức ngày thì nằm ngoài ngân sách.
    static let outsideBudgetFactor = 3

    func parse(_ text: String, rules: [String: String], dailyAllowance: Int) -> [ParsedLine] {
        var lines: [ParsedLine] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if Self.isQuestion(line) {
                lines.append(.question(line))
                continue
            }
            for segment in Self.segments(of: line) {
                for tokens in Self.splitOnAnd(Self.tokens(of: segment)) {
                    if let parsed = Self.parseItem(tokens, rules: rules, dailyAllowance: dailyAllowance) {
                        lines.append(parsed)
                    }
                }
            }
        }
        return lines
    }

    static func isOutsideBudget(amount: Int, dailyAllowance: Int) -> Bool {
        dailyAllowance > 0 && amount > outsideBudgetFactor * dailyAllowance
    }

    // MARK: - Câu hỏi

    private static let questionPhrases = [["bao", "nhiêu"], ["mấy", "lần"], ["hết", "bao"]]

    static func isQuestion(_ line: String) -> Bool {
        if line.hasSuffix("?") { return true }
        let words = TextNormalizer.words(line).map(trimPunctuation)
        return questionPhrases.contains { TextNormalizer.firstIndex(of: $0, in: words) != nil }
    }

    // MARK: - Tách khoản

    /// Tách theo dấu phẩy và chấm phẩy. Dấu phẩy kẹp giữa hai chữ số (`45,000`) thuộc về số tiền.
    private static func segments(of line: String) -> [String] {
        let characters = Array(line)
        var segments: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            var isSeparator = character == ";"
            if character == "," {
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                isSeparator = !(before.isNumber && after.isNumber)
            }
            if isSeparator {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current)
        return segments
    }

    private static func trimPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ".,:!?()\"'"))
    }

    private static func tokens(of segment: String) -> [String] {
        TextNormalizer.words(segment).map(trimPunctuation).filter { !$0.isEmpty }
    }

    /// Tách ở từ "và" khi cả hai vế đều có số, để `bánh và trà 50k` vẫn là một khoản.
    private static func splitOnAnd(_ tokens: [String]) -> [[String]] {
        func hasDigit(_ tokens: some Sequence<String>) -> Bool {
            tokens.contains { $0.contains(where: \.isNumber) }
        }
        var items: [[String]] = []
        var current: [String] = []
        for (index, token) in tokens.enumerated() {
            if TextNormalizer.matches(token, "và"), hasDigit(current), hasDigit(tokens[(index + 1)...]) {
                items.append(current)
                current = []
            } else {
                current.append(token)
            }
        }
        items.append(current)
        return items
    }

    // MARK: - Một khoản

    private static func parseItem(_ tokens: [String], rules: [String: String], dailyAllowance: Int) -> ParsedLine? {
        var (tokens, splitCount) = extractSplit(from: detachSlash(tokens))
        guard !tokens.isEmpty else { return nil }

        let match = AmountParser.find(in: tokens)
        if let match { tokens.removeSubrange(match.range) }

        if let match, let person = loanPerson(in: tokens) {
            return .loan(person: person, amount: match.value)
        }

        let name = tokens.joined(separator: " ")
        var amount = match?.value
        var originalAmount: Int?
        if let total = amount, let count = splitCount {
            originalAmount = total
            amount = share(of: total, among: count)
        } else {
            splitCount = nil
        }
        return .expense(ParsedExpense(
            name: name,
            amount: amount,
            categoryKey: CategoryClassifier.categoryKey(for: name, rules: rules),
            originalAmount: originalAmount,
            splitCount: splitCount,
            isOutsideBudget: amount.map { isOutsideBudget(amount: $0, dailyAllowance: dailyAllowance) } ?? false
        ))
    }

    /// Phần của một người, làm tròn tới 1.000đ.
    private static func share(of total: Int, among count: Int) -> Int {
        let rounded = (2 * total + 1_000 * count) / (2_000 * count) * 1_000
        return rounded > 0 ? rounded : total / count
    }

    // MARK: - Chia tiền

    /// `460k/4` thành `460k` và `/4`.
    private static func detachSlash(_ tokens: [String]) -> [String] {
        tokens.flatMap { token -> [String] in
            guard let slash = token.lastIndex(of: "/"), slash != token.startIndex else { return [token] }
            let head = String(token[..<slash])
            let tail = String(token[token.index(after: slash)...])
            guard splitCount(tail) != nil, AmountParser.isAmount(head) else { return [token] }
            return [head, "/" + tail]
        }
    }

    private static func splitCount(_ text: String) -> Int? {
        if TextNormalizer.matches(text, "đôi") { return 2 }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let count = Int(text), (2...99).contains(count) else { return nil }
        return count
    }

    /// Nhận `chia 4`, `chia4`, `/4`, `/ 4`, có thể kèm chữ "người".
    private static func extractSplit(from tokens: [String]) -> ([String], Int?) {
        var tokens = tokens
        for index in tokens.indices {
            let word = TextNormalizer.lowercased(tokens[index])
            var count: Int?
            var length = 1
            for prefix in ["chia", "/"] where word.hasPrefix(prefix) {
                let rest = String(word.dropFirst(prefix.count))
                if rest.isEmpty, index + 1 < tokens.count {
                    count = splitCount(tokens[index + 1])
                    length = 2
                } else {
                    count = splitCount(rest)
                }
            }
            guard let count else { continue }
            if index + length < tokens.count, TextNormalizer.matches(tokens[index + length], "người") {
                length += 1
            }
            tokens.removeSubrange(index..<index + length)
            return (tokens, count)
        }
        return (tokens, nil)
    }

    // MARK: - Ứng tiền

    /// `ứng cho Minh` hoặc `cho Minh mượn` (đã bỏ số tiền). Trả về tên người, nil nếu không phải khoản ứng.
    private static func loanPerson(in tokens: [String]) -> String? {
        var person: [String]?
        if tokens.count > 2, TextNormalizer.matches(tokens[0], "ứng"), TextNormalizer.matches(tokens[1], "cho") {
            person = Array(tokens.dropFirst(2))
        } else if tokens.count > 2, TextNormalizer.matches(tokens[0], "cho"),
                  let verb = tokens.firstIndex(where: { word in
                      ["mượn", "vay"].contains { TextNormalizer.matches(word, $0) }
                  }), verb > 1 {
            person = Array(tokens[1..<verb]) + tokens[(verb + 1)...]
        }
        guard let person, !person.isEmpty else { return nil }
        return person.joined(separator: " ")
    }
}
