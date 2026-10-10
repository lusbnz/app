import Foundation

/// Một khoản chi đọc từ tệp CSV, sẵn sàng ghi vào máy.
struct ImportedExpense: Equatable, Sendable {
    var date: Date
    var name: String
    var amount: Int
    var categoryKey: String
    var isOutsideBudget: Bool
    var placeName: String?
}

/// Dấu vân tay của một khoản để nhận ra khoản đã có: cùng phút, cùng tên (không phân biệt dấu, hoa thường) và cùng số tiền.
struct ImportSignature: Hashable, Sendable {
    var minute: Int
    var name: String
    var amount: Int

    init(date: Date, name: String, amount: Int) {
        minute = Int((date.timeIntervalSince1970 / 60).rounded(.down))
        self.name = TextNormalizer.keyword(name)
        self.amount = amount
    }
}

enum ImportRejection: Equatable, Sendable {
    case badDate
    case badAmount
    case futureDate
}

struct RejectedRow: Equatable, Sendable {
    /// Thứ tự dòng (không tính dòng trống), tính cả dòng tiêu đề; dòng đầu là 1.
    var line: Int
    var reason: ImportRejection
    var text: String
}

struct CSVImportResult: Equatable, Sendable {
    /// Các khoản sẽ nhập, theo thứ tự trong tệp.
    var rows: [ImportedExpense] = []
    /// Dòng giống hệt một khoản đã có trên máy (hoặc đã xuất hiện trước trong tệp nếu máy có sẵn một khoản).
    var duplicates = 0
    /// Dòng tiền vào (thu nhập), Pennyline chỉ ghi khoản chi.
    var skippedIncome = 0
    var rejected: [RejectedRow] = []

    var total: Int { rows.reduce(0) { $0 + $1.amount } }
    var firstDate: Date? { rows.map(\.date).min() }
    var lastDate: Date? { rows.map(\.date).max() }
}

enum CSVImportFailure: Error, Equatable, Sendable {
    /// Không có dòng nào.
    case empty
    /// Không nhận ra cột ngày hoặc cột số tiền.
    case missingColumns(date: Bool, amount: Bool)
}

/// Đọc tệp CSV thành các khoản chi. Hiểu tệp Pennyline tự xuất, và tệp của ngân hàng hay ứng dụng khác miễn là có cột ngày và cột số tiền.
/// Cột nhận theo tên tiêu đề (không phân biệt dấu, hoa thường): ngày, giờ, tên hoặc nội dung, số tiền (hoặc ghi nợ và ghi có), danh mục,
/// ngoài ngân sách, nơi. Số tiền có cả âm lẫn dương thì số âm là chi, số dương là thu nhập và bị bỏ.
enum CSVImporter {
    struct CategoryName: Equatable, Sendable {
        var key: String
        var name: String
    }

    struct Options: Sendable {
        /// Luật danh mục đã dạy (khóa đã chuẩn hóa), để đoán danh mục từ tên khi tệp không có cột danh mục.
        var rules: [String: String] = [:]
        /// Danh mục tự thêm, để khớp tên trong cột danh mục.
        var customCategories: [CategoryName] = []
        /// Các khoản đã có trên máy, để bỏ dòng trùng.
        var existing: [ImportSignature] = []
        var now: Date
        var calendar: Calendar
    }

    private enum Role: CaseIterable {
        case outside, place, category, time, date, credit, debit, amount, name
    }

    /// Tiêu đề đã bỏ dấu và ký tự không phải chữ số. Hậu tố `$` nghĩa là phải khớp nguyên cả tiêu đề, không thì chỉ cần bắt đầu bằng.
    private static let aliases: [Role: [String]] = [
        .outside: ["ngoaingansach", "outsidebudget"],
        .place: ["noi$", "diadiem", "place", "location", "venue"],
        .category: ["danhmuc", "category", "nhom", "phanloai", "loai$"],
        .time: ["gio$", "time$", "giogiaodich"],
        .date: ["ngay", "date", "thoigian", "datetime", "transactiondate", "bookingdate"],
        .credit: ["ghico", "credit", "tienvao", "nop$", "thu$"],
        .debit: ["ghino", "debit", "tienra", "rut$"],
        .amount: ["sotien", "amount", "giatri", "tongtien", "total", "value", "tien$", "chi$"],
        .name: ["ten", "name", "noidung", "mota", "description", "ghichu", "note", "memo", "diengiai", "details", "title", "payee", "merchant"],
    ]

    /// Tên danh mục có sẵn (đã bỏ dấu) theo cả tiếng Việt lẫn tiếng Anh, để tệp xuất ở ngôn ngữ nào cũng nhập lại được.
    private static let builtInNames: [String: String] = {
        let table: [String: [String]] = [
            "food": ["food", "an uong", "do an"],
            "transport": ["transport", "transportation", "di lai", "giao thong"],
            "shopping": ["shopping", "mua sam"],
            "bills": ["bills", "bill", "hoa don"],
            "health": ["health", "suc khoe", "y te"],
            "fun": ["fun", "entertainment", "giai tri"],
            "other": ["other", "khac"],
        ]
        var result: [String: String] = [:]
        for (key, names) in table { for name in names { result[name] = key } }
        return result
    }()

    static func importExpenses(from text: String, options: Options) -> Result<CSVImportResult, CSVImportFailure> {
        let table = CSVParser.rows(from: text)
        guard !table.isEmpty else { return .failure(.empty) }

        // Dòng tiêu đề là dòng đầu (trong vài dòng đầu) có cả cột ngày lẫn cột số tiền; các dòng phía trên (nếu có) bị bỏ.
        var headerIndex: Int?
        var columns: [Role: Int] = [:]
        var sawDate = false, sawAmount = false
        for (index, row) in table.prefix(6).enumerated() {
            let found = columnRoles(in: row)
            sawDate = sawDate || found[.date] != nil
            sawAmount = sawAmount || found[.amount] != nil || found[.debit] != nil
            if found[.date] != nil, found[.amount] != nil || found[.debit] != nil {
                headerIndex = index
                columns = found
                break
            }
        }
        guard let headerIndex else { return .failure(.missingColumns(date: !sawDate, amount: !sawAmount)) }

        struct Parsed {
            var date: Date
            var value: ImportAmount.Value
            var cells: [String]
        }
        var result = CSVImportResult()
        var parsed: [Parsed] = []
        let tomorrow = options.now.addingTimeInterval(86_400)

        func cell(_ role: Role, in row: [String]) -> String {
            guard let index = columns[role], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for (offset, row) in table.enumerated().dropFirst(headerIndex + 1) {
            let line = offset + 1
            let summary = row.joined(separator: ",")
            let timeText = cell(.time, in: row)
            guard let date = ImportDate.parse(cell(.date, in: row), time: timeText.isEmpty ? nil : timeText, calendar: options.calendar) else {
                result.rejected.append(RejectedRow(line: line, reason: .badDate, text: summary))
                continue
            }
            if date > tomorrow {
                result.rejected.append(RejectedRow(line: line, reason: .futureDate, text: summary))
                continue
            }
            if columns[.amount] == nil {
                // Tệp tách cột ghi nợ và ghi có: ghi nợ là chi, chỉ có ghi có thì là tiền vào.
                if let debit = ImportAmount.parse(cell(.debit, in: row)) {
                    parsed.append(Parsed(date: date, value: debit, cells: row))
                } else if ImportAmount.parse(cell(.credit, in: row)) != nil {
                    result.skippedIncome += 1
                } else {
                    result.rejected.append(RejectedRow(line: line, reason: .badAmount, text: summary))
                }
            } else if let value = ImportAmount.parse(cell(.amount, in: row)) {
                parsed.append(Parsed(date: date, value: value, cells: row))
            } else {
                result.rejected.append(RejectedRow(line: line, reason: .badAmount, text: summary))
            }
        }

        // Cột số tiền có cả âm lẫn dương: âm là chi, dương là thu nhập.
        let signed = columns[.amount] != nil && parsed.contains { $0.value.isNegative }
        var counts: [ImportSignature: Int] = [:]
        for signature in options.existing { counts[signature, default: 0] += 1 }

        for item in parsed {
            if signed && !item.value.isNegative {
                result.skippedIncome += 1
                continue
            }
            let name = unescapedName(cell(.name, in: item.cells))
            let signature = ImportSignature(date: item.date, name: name, amount: item.value.dong)
            if let remaining = counts[signature], remaining > 0 {
                counts[signature] = remaining - 1
                result.duplicates += 1
                continue
            }
            let place = unescapedName(cell(.place, in: item.cells))
            result.rows.append(ImportedExpense(
                date: item.date, name: name, amount: item.value.dong,
                categoryKey: categoryKey(named: cell(.category, in: item.cells), expenseName: name, options: options),
                isOutsideBudget: isTrue(cell(.outside, in: item.cells)),
                placeName: place.isEmpty ? nil : place
            ))
        }
        return .success(result)
    }

    // MARK: - Cột

    private static func columnRoles(in header: [String]) -> [Role: Int] {
        var found: [Role: Int] = [:]
        for (index, title) in header.enumerated() {
            let key = headerKey(title)
            guard !key.isEmpty else { continue }
            for role in Role.allCases where found[role] == nil {
                if matches(key, aliases: aliases[role] ?? []) {
                    found[role] = index
                    break
                }
            }
        }
        return found
    }

    private static func headerKey(_ title: String) -> String {
        TextNormalizer.fold(title).filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func matches(_ key: String, aliases: [String]) -> Bool {
        aliases.contains { alias in
            alias.hasSuffix("$") ? key == alias.dropLast() : key.hasPrefix(alias)
        }
    }

    // MARK: - Ô

    /// Bản Pennyline xuất thêm dấu nháy đơn trước chữ bắt đầu bằng `= + - @` để bảng tính không hiểu là công thức; nhập lại thì bỏ dấu đó.
    private static func unescapedName(_ text: String) -> String {
        guard text.hasPrefix("'"), let second = text.dropFirst().unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(second) else { return text }
        return String(text.dropFirst())
    }

    private static func isTrue(_ text: String) -> Bool {
        let key = TextNormalizer.keyword(text)
        return !key.isEmpty && !["0", "no", "false", "khong", "n"].contains(key)
    }

    /// Khớp tên ở cột danh mục (có sẵn hoặc tự thêm); không khớp thì đoán từ tên khoản bằng luật đã dạy và từ điển, cuối cùng là "khác".
    private static func categoryKey(named title: String, expenseName: String, options: Options) -> String {
        let folded = TextNormalizer.keyword(title)
        if !folded.isEmpty {
            if let custom = options.customCategories.first(where: { TextNormalizer.keyword($0.name) == folded }) { return custom.key }
            if let builtIn = builtInNames[folded] { return builtIn }
        }
        return CategoryClassifier.categoryKey(for: expenseName, rules: options.rules)
    }
}
