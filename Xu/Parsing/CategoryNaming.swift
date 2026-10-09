import Foundation

/// Tên và khóa của danh mục tự thêm.
enum CategoryNaming {
    static let maxLength = 20
    static let customPrefix = "custom-"

    enum Failure: Error, Equatable, Sendable {
        case empty
        case tooLong
        case duplicate
    }

    static func makeKey(id: UUID) -> String {
        customPrefix + id.uuidString.lowercased()
    }

    static func isCustom(_ key: String) -> Bool {
        key.hasPrefix(customPrefix)
    }

    /// Gộp khoảng trắng, rồi kiểm tra rỗng, độ dài và trùng với tên đã có (không phân biệt hoa thường và dấu).
    static func validate(_ name: String, existing: [String]) -> Result<String, Failure> {
        let cleaned = TextNormalizer.words(name).joined(separator: " ")
        guard !cleaned.isEmpty else { return .failure(.empty) }
        guard cleaned.count <= maxLength else { return .failure(.tooLong) }
        let key = TextNormalizer.keyword(cleaned)
        guard !existing.contains(where: { TextNormalizer.keyword($0) == key }) else { return .failure(.duplicate) }
        return .success(cleaned)
    }
}
