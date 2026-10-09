import Foundation

/// Đổi số tiền đọc bằng chữ thành chữ số, để bộ tách đọc được lời nói:
/// `bốn mươi lăm nghìn` thành `45000`, `hai trăm rưỡi` thành `250`, `một triệu hai` thành `1200000`.
/// Chỉ đổi dãy từ có dấu hiệu là tiền (trăm, nghìn, ngàn, triệu, mươi); `chia ba` hay `ba mẹ` giữ nguyên.
enum SpokenNumbers {
    static func normalize(_ text: String) -> String {
        let tokens = TextNormalizer.words(text)
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            guard isNumberWord(core(tokens[index])) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            var end = index
            while end < tokens.count, isNumberWord(core(tokens[end])) { end += 1 }
            let run = tokens[index..<end].map(core)
            if let value = value(of: run) {
                output.append(String(value) + punctuation(of: tokens[end - 1]))
            } else {
                output.append(contentsOf: tokens[index..<end])
            }
            index = end
        }
        return output.joined(separator: " ")
    }

    // MARK: - Từ

    private static let punctuationSet = CharacterSet(charactersIn: ".,;:!?")

    private static func core(_ token: String) -> String {
        token.trimmingCharacters(in: punctuationSet)
    }

    private static func punctuation(of token: String) -> String {
        String(token.dropFirst(core(token).count))
    }

    private static let digits: [(value: Int, words: [String])] = [
        (0, ["không"]), (1, ["một", "mốt"]), (2, ["hai"]), (3, ["ba"]), (4, ["bốn", "tư"]),
        (5, ["năm", "lăm"]), (6, ["sáu"]), (7, ["bảy"]), (8, ["tám"]), (9, ["chín"]),
    ]

    private static func digit(_ token: String) -> Int? {
        digits.first { entry in entry.words.contains { TextNormalizer.matches(token, $0) } }?.value
    }

    private static func isWord(_ token: String, _ words: [String]) -> Bool {
        words.contains { TextNormalizer.matches(token, $0) }
    }

    private static func isNumberWord(_ token: String) -> Bool {
        digit(token) != nil || isWord(token, ["mười", "mươi", "trăm", "nghìn", "ngàn", "triệu", "lẻ", "linh", "rưỡi"])
    }

    // MARK: - Giá trị

    /// Giá trị của một dãy từ số, nil khi không phải số tiền hợp lệ.
    private static func value(of words: [String]) -> Int? {
        var total = 0
        var lastMagnitude = Int.max
        var hundreds: Int?
        var tens: Int?
        var pending: Int?       // chữ số chưa biết là hàng đơn vị hay hàng chục
        var units: Int?
        var sawOdd = false
        var hasSignal = false
        var afterMagnitude = false  // từ liền trước là trăm, nghìn hay triệu
        var lastMagnitudeValue = 0
        var halfBase = 0        // nửa của hàng vừa đọc, cho "rưỡi"
        var half = 0

        func group() -> Int { (hundreds ?? 0) * 100 + (tens ?? 0) + (units ?? pending ?? 0) }
        func reset() { hundreds = nil; tens = nil; pending = nil; units = nil; sawOdd = false }

        for word in words {
            let followsMagnitude = afterMagnitude
            afterMagnitude = false
            if let d = digit(word) {
                if tens != nil || sawOdd {
                    guard units == nil else { return nil }
                    units = d
                } else {
                    guard pending == nil else { return nil }
                    pending = d
                }
            } else if isWord(word, ["mươi"]), let d = pending {
                guard tens == nil else { return nil }
                tens = d * 10
                pending = nil
                hasSignal = true
            } else if isWord(word, ["mười"]) {
                guard pending == nil, tens == nil else { return nil }
                tens = 10
            } else if isWord(word, ["trăm"]) {
                guard let d = pending, hundreds == nil, tens == nil else { return nil }
                hundreds = d
                pending = nil
                hasSignal = true
                halfBase = 50
                afterMagnitude = true
            } else if isWord(word, ["lẻ", "linh"]) {
                guard hundreds != nil else { return nil }
                sawOdd = true
            } else if isWord(word, ["nghìn", "ngàn", "triệu"]) {
                let magnitude = isWord(word, ["triệu"]) ? 1_000_000 : 1_000
                let value = group()
                guard value > 0, magnitude < lastMagnitude else { return nil }
                total += value * magnitude
                lastMagnitude = magnitude
                lastMagnitudeValue = magnitude
                halfBase = magnitude / 2
                reset()
                hasSignal = true
                afterMagnitude = true
            } else if isWord(word, ["rưỡi"]) {
                guard followsMagnitude, half == 0 else { return nil }
                half = halfBase
            } else {
                return nil
            }
        }
        guard hasSignal else { return nil }

        // Phần đọc thêm sau một hàng triệu hay nghìn: "một triệu hai", "một triệu hai trăm".
        var trailing = group()
        if trailing > 0 {
            if hundreds == nil, tens == nil, units == nil, let lone = pending, lastMagnitudeValue > 0 {
                trailing = lone * lastMagnitudeValue / 10
            } else if hundreds != nil, tens == nil, units == nil, pending != nil {
                // "hai trăm năm" là 250 khi nói về tiền.
                trailing = (hundreds ?? 0) * 100 + (pending ?? 0) * 10
                if lastMagnitudeValue == 1_000_000 { trailing *= 1_000 }
            } else if lastMagnitudeValue == 1_000_000 {
                trailing *= 1_000
            }
        }
        let result = total + trailing + half
        return result > 0 ? result : nil
    }
}
