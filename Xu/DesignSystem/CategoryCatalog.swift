import SwiftUI

/// Một danh mục để hiển thị, có sẵn hay tự thêm.
struct CategoryInfo: Identifiable, Equatable {
    let key: String
    let title: String
    let color: Color
    let isCustom: Bool

    var id: String { key }
}

/// Danh mục có sẵn cộng danh mục tự thêm. Khóa không còn tồn tại (đã xóa) hiện là "khác".
struct CategoryCatalog {
    let all: [CategoryInfo]

    init(custom: [CustomCategory]) {
        let builtIn = SpendingCategory.allCases.map {
            CategoryInfo(key: $0.rawValue, title: String(localized: $0.title), color: $0.color, isCustom: false)
        }
        let added = custom.sorted { ($0.createdAt, $0.key) < ($1.createdAt, $1.key) }.map {
            CategoryInfo(key: $0.key, title: $0.name, color: SpendingCategory.other.color, isCustom: true)
        }
        all = builtIn + added
    }

    func info(for key: String) -> CategoryInfo {
        all.first { $0.key == key } ?? all.first { $0.key == SpendingCategory.other.rawValue } ?? all[0]
    }

    /// Tên hiện cho từng khóa, để đưa vào bảng số liệu của Hỏi Xu.
    var titles: [String: String] {
        Dictionary(all.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
    }
}
