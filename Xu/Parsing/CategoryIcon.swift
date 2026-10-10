import Foundation

/// Biểu tượng (SF Symbols) của danh mục. Có sẵn thì cố định; tự thêm thì người dùng chọn,
/// và Pennyline gợi ý trước theo tên ("thú cưng" ra chân thú) bằng cùng cách khớp cụm từ của bộ phân loại.
enum CategoryIcon {
    /// Biểu tượng khi danh mục tự thêm chưa chọn gì.
    static let fallback = "tag"

    static func symbol(for category: SpendingCategory) -> String {
        switch category {
        case .food: "fork.knife"
        case .transport: "car"
        case .shopping: "bag"
        case .bills: "doc.text"
        case .health: "cross.case"
        case .fun: "gamecontroller"
        case .other: "ellipsis.circle"
        }
    }

    /// Bảng chọn cho danh mục tự thêm.
    static let palette: [String] = [
        "pawprint", "house", "book", "graduationcap", "airplane", "gift",
        "heart", "cart", "tshirt", "scissors", "wrench.and.screwdriver", "pill",
        "dumbbell", "music.note", "camera", "fuelpump", "bus", "bicycle",
        "leaf", "drop", "bolt", "wifi", "cup.and.saucer", "birthday.cake",
        "person.2", "banknote", "tag", "star",
    ]

    private static let hints: [(symbol: String, phrases: [String])] = [
        ("pawprint", ["thú cưng", "chó", "mèo", "thú y", "pet"]),
        ("house", ["nhà", "thuê nhà", "tiền nhà", "sửa nhà", "nội thất"]),
        ("book", ["sách", "truyện", "đọc"]),
        ("graduationcap", ["học", "học phí", "khóa học", "trường", "con"]),
        ("airplane", ["du lịch", "vé máy bay", "chuyến đi", "khách sạn"]),
        ("gift", ["quà", "tặng", "mừng", "đám cưới", "lì xì"]),
        ("heart", ["từ thiện", "ủng hộ", "hẹn hò", "người yêu"]),
        ("cart", ["chợ", "siêu thị", "đi chợ"]),
        ("tshirt", ["quần áo", "thời trang", "giặt"]),
        ("scissors", ["tóc", "cắt tóc", "làm đẹp", "spa", "nail"]),
        ("wrench.and.screwdriver", ["sửa", "sửa chữa", "dụng cụ"]),
        ("pill", ["thuốc", "vitamin"]),
        ("dumbbell", ["gym", "thể thao", "yoga"]),
        ("music.note", ["nhạc", "concert"]),
        ("camera", ["ảnh", "chụp ảnh", "máy ảnh"]),
        ("fuelpump", ["xăng", "đổ xăng"]),
        ("bus", ["xe buýt", "xe bus", "metro"]),
        ("bicycle", ["xe đạp"]),
        ("leaf", ["cây", "hoa", "vườn"]),
        ("wifi", ["wifi", "mạng", "internet"]),
        ("cup.and.saucer", ["cà phê", "cafe", "trà"]),
        ("birthday.cake", ["bánh", "sinh nhật", "tiệc"]),
        ("person.2", ["bạn bè", "gia đình", "biếu"]),
        ("banknote", ["tiết kiệm", "đầu tư", "trả nợ", "nợ"]),
    ]

    private static let entries: [(symbol: String, phrase: [String])] = hints.flatMap { hint in
        hint.phrases.map { (hint.symbol, TextNormalizer.words($0)) }
    }

    /// Biểu tượng gợi ý theo tên danh mục; cụm khớp dài hơn thắng, hòa thì cụm đứng trước trong tên thắng.
    /// Không khớp gì thì trả về `fallback`.
    static func suggest(for name: String) -> String {
        let typed = TextNormalizer.words(name)
        var best: (symbol: String, length: Int, index: Int)?
        for entry in entries {
            guard let index = TextNormalizer.firstIndex(of: entry.phrase, in: typed) else { continue }
            if let current = best, (current.length, -current.index) >= (entry.phrase.count, -index) { continue }
            best = (entry.symbol, entry.phrase.count, index)
        }
        return best?.symbol ?? fallback
    }

    /// Biểu tượng dùng để hiển thị: rỗng hoặc không thuộc bảng chọn (dữ liệu lạ từ iCloud) thì lùi về `fallback`.
    static func resolved(_ name: String) -> String {
        palette.contains(name) ? name : fallback
    }
}
