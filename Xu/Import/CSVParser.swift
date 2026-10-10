import Foundation

/// Đọc CSV theo RFC 4180: ô đặt trong ngoặc kép có thể chứa dấu phân cách, xuống dòng và `""`.
/// Nhận ra dấu phân cách `,`, `;` hoặc tab theo dòng đầu; bỏ BOM và các dòng trống.
enum CSVParser {
    static func rows(from text: String) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let delimiter = delimiter(of: scalars)

        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRow() {
            endField()
            // Dòng chỉ có một ô trắng là dòng trống.
            if row.count > 1 || !row[0].trimmingCharacters(in: .whitespaces).isEmpty { rows.append(row) }
            row = []
        }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\"" && field.isEmpty {
                inQuotes = true
            } else if scalar == delimiter {
                endField()
            } else if scalar == "\r" {
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                endRow()
            } else if scalar == "\n" {
                endRow()
            } else {
                field.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// Số dòng đầu dùng để đoán dấu phân cách. Tệp ngân hàng thường có vài dòng mở đầu không có dấu nào.
    private static let sampleLines = 12

    /// Dấu cắt các dòng đầu ra cùng một số ô nhiều dòng nhất (ngoài ngoặc kép); hòa thì ưu tiên dấu phẩy, rồi chấm phẩy, rồi tab.
    private static func delimiter(of scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        let candidates: [Unicode.Scalar] = [",", ";", "\t"]
        var lines: [[Int]] = []
        var current = [0, 0, 0]
        var hasContent = false
        var inQuotes = false
        for scalar in scalars {
            if scalar == "\"" {
                inQuotes.toggle()
                hasContent = true
            } else if !inQuotes && (scalar == "\n" || scalar == "\r") {
                if hasContent { lines.append(current) }
                current = [0, 0, 0]
                hasContent = false
                if lines.count == sampleLines { break }
            } else {
                if !inQuotes, let index = candidates.firstIndex(of: scalar) { current[index] += 1 }
                if !scalar.properties.isWhitespace { hasContent = true }
            }
        }
        if hasContent, lines.count < sampleLines { lines.append(current) }

        var best = (index: 0, score: 0)
        for index in candidates.indices {
            var frequency: [Int: Int] = [:]
            for count in lines.map({ $0[index] }) where count > 0 { frequency[count, default: 0] += 1 }
            // Số ô thường gặp nhất: nhiều dòng cùng số dấu là dấu đúng; số dấu lớn hơn thắng khi bằng số dòng.
            guard let common = frequency.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { continue }
            let score = common.value * 1000 + common.key
            if score > best.score { best = (index, score) }
        }
        return candidates[best.index]
    }
}
