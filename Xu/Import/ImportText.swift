import Foundation

/// Đọc chữ từ tệp người dùng chọn.
enum ImportText {
    /// Tệp lớn hơn mức này bị từ chối, để không nạp cả tệp rác vào bộ nhớ.
    static let maxBytes = 20_000_000

    /// UTF-8 (có hoặc không BOM), UTF-16 có BOM, rồi Windows-1252 (bảng tính cũ lưu "CSV" theo bảng mã này). Nil khi tệp rỗng.
    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }
}
