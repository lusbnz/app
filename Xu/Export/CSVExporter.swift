import Foundation

/// Một dòng của tệp CSV. Tên danh mục đã tra sẵn, nên tệp đọc được mà không cần Nhẩm.
struct ExportRecord: Equatable, Sendable {
    var date: Date
    var name: String
    var amount: Int
    var categoryTitle: String
    var isOutsideBudget: Bool
    var placeName: String?
}

/// Xuất khoản chi ra CSV (RFC 4180) để mở bằng Excel hoặc Numbers.
enum CSVExporter {
    static let header = ["Ngày", "Giờ", "Tên", "Số tiền (đồng)", "Danh mục", "Ngoài ngân sách", "Nơi"]

    /// Cũ đến mới, dòng kết thúc CRLF, có BOM UTF-8 để Excel đọc đúng tiếng Việt.
    static func csv(_ records: [ExportRecord], calendar: Calendar) -> String {
        let sorted = records.sorted { $0.date < $1.date }
        let rows = [header] + sorted.map { record in
            [
                format(record.date, "yyyy-MM-dd", calendar),
                format(record.date, "HH:mm", calendar),
                record.name,
                String(record.amount),
                record.categoryTitle,
                record.isOutsideBudget ? "x" : "",
                record.placeName ?? "",
            ]
        }
        let body = rows.map { $0.enumerated().map { escape($1, isNumber: $0 == 3) }.joined(separator: ",") }
            .joined(separator: "\r\n")
        return "\u{FEFF}" + body + "\r\n"
    }

    /// "xu-chi-tieu-2026-10-10.csv"
    static func fileName(now: Date, calendar: Calendar) -> String {
        "xu-chi-tieu-\(format(now, "yyyy-MM-dd", calendar)).csv"
    }

    /// Bọc dấu ngoặc kép khi có dấu phẩy, ngoặc kép hoặc xuống dòng. Ô chữ bắt đầu bằng `= + - @`
    /// bị bảng tính hiểu là công thức, nên thêm dấu nháy đơn ở đầu.
    static func escape(_ field: String, isNumber: Bool = false) -> String {
        var text = field
        if !isNumber, let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
            text = "'" + text
        }
        guard text.unicodeScalars.contains(where: { ",\"\r\n".unicodeScalars.contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
