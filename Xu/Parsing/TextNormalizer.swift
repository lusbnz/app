import Foundation

enum TextNormalizer {
    /// Chữ thường, dạng dựng sẵn (NFC), giữ nguyên dấu.
    static func lowercased(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Chữ thường, bỏ dấu, `đ` thành `d`.
    static func fold(_ text: String) -> String {
        lowercased(text)
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// Khóa chuẩn hóa cho luật danh mục: bỏ dấu, chữ thường, gộp khoảng trắng.
    static func keyword(_ text: String) -> String {
        words(fold(text)).joined(separator: " ")
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Chữ người dùng gõ khớp một từ trong từ điển khi gõ đúng dấu hoặc bỏ hẳn dấu.
    /// Nhờ vậy `be` và `pho` khớp, còn `bé` hay `phố` thì không.
    static func matches(_ typed: String, _ word: String) -> Bool {
        let typed = lowercased(typed)
        return typed == word || typed == fold(word)
    }

    /// Vị trí đầu tiên mà cụm từ điển xuất hiện trọn vẹn trong các từ đã gõ.
    static func firstIndex(of phrase: [String], in typed: [String]) -> Int? {
        guard !phrase.isEmpty, typed.count >= phrase.count else { return nil }
        for start in 0...(typed.count - phrase.count)
        where phrase.indices.allSatisfy({ matches(typed[start + $0], phrase[$0]) }) {
            return start
        }
        return nil
    }
}
