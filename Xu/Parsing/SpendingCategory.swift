import Foundation

enum SpendingCategory: String, CaseIterable, Sendable, Identifiable {
    case food, transport, shopping, bills, health, fun, other

    var id: String { rawValue }

    init(key: String) {
        self = SpendingCategory(rawValue: key) ?? .other
    }
}

/// Phân loại theo thứ tự: luật người dùng đã dạy, từ điển có sẵn, rồi `other`.
enum CategoryClassifier {
    private static let dictionary: [(category: SpendingCategory, phrases: [String])] = [
        (.food, [
            "phở", "cơm", "bún", "cf", "cafe", "cà phê", "trà", "nhậu", "bánh", "mì", "cháo",
            "xôi", "lẩu", "bia", "trà sữa", "ăn", "chè", "kem", "sữa", "nướng", "hủ tiếu",
            "bánh mì", "trà đá", "nước", "gà", "ốc", "highlands",
        ]),
        (.transport, [
            "grab", "be", "xăng", "gửi xe", "taxi", "xe ôm", "xe buýt", "vé xe", "gojek",
            "xanh sm", "rửa xe", "sửa xe", "vé máy bay", "vé tàu",
        ]),
        (.shopping, [
            "áo", "quần", "giày", "dép", "tai nghe", "sách", "shopee", "lazada", "tiki",
            "mỹ phẩm", "túi", "siêu thị",
        ]),
        (.bills, [
            "tiền điện", "tiền nước", "internet", "wifi", "điện thoại", "4g", "nạp tiền",
        ]),
        (.health, ["thuốc", "khám", "bác sĩ", "nha khoa", "bệnh viện", "gym"]),
        (.fun, ["phim", "game", "karaoke", "netflix", "spotify", "du lịch"]),
    ]

    private static let entries: [(category: SpendingCategory, phrase: [String])] =
        dictionary.flatMap { group in
            group.phrases.map { (group.category, TextNormalizer.words($0)) }
        }

    static func categoryKey(for name: String, rules: [String: String]) -> String {
        let key = TextNormalizer.keyword(name)
        if let taught = rules[key] { return taught }

        let foldedWords = TextNormalizer.words(key)
        let taughtPhrase = rules
            .filter { rule in
                let phrase = TextNormalizer.words(rule.key)
                return TextNormalizer.firstIndex(of: phrase, in: foldedWords) != nil
            }
            .max { ($0.key.count, $1.key) < ($1.key.count, $0.key) }
        if let taughtPhrase { return taughtPhrase.value }

        let typedWords = TextNormalizer.words(name)
        var best: (category: SpendingCategory, length: Int, index: Int)?
        for entry in entries {
            guard let index = TextNormalizer.firstIndex(of: entry.phrase, in: typedWords) else { continue }
            if let current = best,
               (current.length, -current.index) >= (entry.phrase.count, -index) { continue }
            best = (entry.category, entry.phrase.count, index)
        }
        return (best?.category ?? .other).rawValue
    }
}
