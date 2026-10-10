import Foundation
import Testing
@testable import Xu

struct CSVParserTests {
    @Test func readsPlainRows() {
        #expect(CSVParser.rows(from: "a,b,c\n1,2,3\n") == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func readsQuotedFieldsWithCommasQuotesAndNewlines() {
        let text = "name,note\r\n\"phở, bò\",\"nói \"\"ngon\"\"\"\r\n\"a\nb\",x\r\n"
        #expect(CSVParser.rows(from: text) == [["name", "note"], ["phở, bò", "nói \"ngon\""], ["a\nb", "x"]])
    }

    @Test func dropsBOMBlankLinesAndHandlesNoTrailingNewline() {
        #expect(CSVParser.rows(from: "\u{FEFF}a,b\n\n  \n1,2") == [["a", "b"], ["1", "2"]])
    }

    @Test func keepsEmptyCells() {
        #expect(CSVParser.rows(from: "a,,c\n,,\n\"\",x,") == [["a", "", "c"], ["", "", ""], ["", "x", ""]])
    }

    @Test func detectsSemicolonAndTabDelimiters() {
        #expect(CSVParser.rows(from: "a;b;c\n1;2;3") == [["a", "b", "c"], ["1", "2", "3"]])
        #expect(CSVParser.rows(from: "a\tb\n1\t2") == [["a", "b"], ["1", "2"]])
    }

    @Test func commasInsideQuotesDoNotChooseTheDelimiter() {
        #expect(CSVParser.rows(from: "\"a,b,c\";d\n1;2") == [["a,b,c", "d"], ["1", "2"]])
    }

    @Test func introLinesWithoutDelimitersDoNotHideTheRealOne() {
        let text = "Sao kê tài khoản\nTừ ngày 01/10, đến 09/10\nNgày;Tên;Tiền\n05/10;a;1\n06/10;b;2"
        let rows = CSVParser.rows(from: text)
        #expect(rows.last == ["06/10", "b", "2"])
        #expect(rows.count == 5)
    }

    @Test func unquotedDecimalCommasDoNotBreakASemicolonFile() {
        #expect(CSVParser.rows(from: "a;b;c\n1;2,5;3\n4;5,5;6") == [["a", "b", "c"], ["1", "2,5", "3"], ["4", "5,5", "6"]])
    }

    @Test func readsWhatTheExporterWrites() {
        let records = [
            ExportRecord(date: TestClock.date(2026, 10, 5, 7), name: "phở, bò", amount: 45_000, categoryTitle: "ăn uống", isOutsideBudget: false, placeName: nil),
            ExportRecord(date: TestClock.date(2026, 10, 6, 9), name: "nói \"ngon\"", amount: 1_200_000, categoryTitle: "mua sắm", isOutsideBudget: true, placeName: "Highlands, Q1"),
        ]
        let rows = CSVParser.rows(from: CSVExporter.csv(records, calendar: TestClock.calendar))
        #expect(rows.count == 3)
        #expect(rows[0] == CSVExporter.header)
        #expect(rows[1][2] == "phở, bò" && rows[2][2] == "nói \"ngon\"" && rows[2][6] == "Highlands, Q1")
    }
}

struct ImportFormatTests {
    private let calendar = TestClock.calendar

    @Test(arguments: [
        ("2026-10-05", TestClock.date(2026, 10, 5, 12)),
        ("2026-10-05 14:30", TestClock.date(2026, 10, 5, 14)),
        ("2026-10-05T14:30:00", TestClock.date(2026, 10, 5, 14)),
        ("05/10/2026", TestClock.date(2026, 10, 5, 12)),
        ("5-10-2026", TestClock.date(2026, 10, 5, 12)),
        ("5.10.26", TestClock.date(2026, 10, 5, 12)),
        ("2026/10/05", TestClock.date(2026, 10, 5, 12)),
    ])
    func readsDatesDayFirstUnlessYearLeads(text: String, expected: Date) {
        let date = ImportDate.parse(text, calendar: calendar)
        #expect(date.map { calendar.dateComponents([.year, .month, .day], from: $0) } == calendar.dateComponents([.year, .month, .day], from: expected))
    }

    @Test(arguments: [
        ("2026-10-05 14:30", 14, 30),
        ("5/10/2026 2:30 PM", 14, 30),
        ("5/10/2026 2:30 CH", 14, 30),
        ("5/10/2026 12:15 AM", 0, 15),
        ("5/10/2026 12:15 PM", 12, 15),
        ("2026-10-05T07:45:10", 7, 45),
    ])
    func readsClockTimesInOneOrTwelveHourForms(text: String, hour: Int, minute: Int) throws {
        let date = try #require(ImportDate.parse(text, calendar: calendar))
        #expect(calendar.component(.hour, from: date) == hour)
        #expect(calendar.component(.minute, from: date) == minute)
    }

    @Test func aSeparateTimeColumnFillsInWhenTheDateHasNoTime() throws {
        let date = try #require(ImportDate.parse("05/10/2026", time: "07:45", calendar: calendar))
        #expect(calendar.component(.hour, from: date) == 7 && calendar.component(.minute, from: date) == 45)
        let withOwnTime = try #require(ImportDate.parse("05/10/2026 09:00", time: "07:45", calendar: calendar))
        #expect(calendar.component(.hour, from: withOwnTime) == 9)
    }

    @Test(arguments: ["", "abc", "31/02/2026", "2026-13-01", "2026-10", "1/2/345", "32/10/2026"])
    func rejectsTextThatIsNotARealDate(text: String) {
        #expect(ImportDate.parse(text, calendar: calendar) == nil)
    }

    @Test(arguments: [
        ("45000", 45_000, false),
        ("45.000", 45_000, false),
        ("45,000đ", 45_000, false),
        ("45 000 VND", 45_000, false),
        ("1.234.567", 1_234_567, false),
        ("1.234.567,50", 1_234_567, false),
        ("1,234,567.00", 1_234_567, false),
        ("45000.5", 45_000, false),
        ("-45.000", 45_000, true),
        ("\u{2212}45.000", 45_000, true),
        ("(45.000)", 45_000, true),
        ("Chi 120.000₫", 120_000, false),
    ])
    func readsAmountsInDong(text: String, dong: Int, negative: Bool) {
        #expect(ImportAmount.parse(text) == ImportAmount.Value(dong: dong, isNegative: negative))
    }

    @Test(arguments: ["", "abc", "0", "0,00", "-", "đ"])
    func rejectsTextWithoutAPositiveAmount(text: String) {
        #expect(ImportAmount.parse(text) == nil)
    }
}

struct CSVImporterTests {
    private let calendar = TestClock.calendar

    private func options(
        rules: [String: String] = [:], custom: [CSVImporter.CategoryName] = [], existing: [ImportSignature] = []
    ) -> CSVImporter.Options {
        CSVImporter.Options(rules: rules, customCategories: custom, existing: existing, now: TestClock.now, calendar: calendar)
    }

    private func run(_ text: String, _ options: CSVImporter.Options? = nil) throws -> CSVImportResult {
        try CSVImporter.importExpenses(from: text, options: options ?? self.options()).get()
    }

    @Test func readsTheFileTheAppExports() throws {
        let records = [
            ExportRecord(date: TestClock.date(2026, 10, 5, 7), name: "phở", amount: 45_000, categoryTitle: "ăn uống", isOutsideBudget: false, placeName: nil),
            ExportRecord(date: TestClock.date(2026, 10, 6, 9), name: "tai nghe", amount: 1_200_000, categoryTitle: "mua sắm", isOutsideBudget: true, placeName: "Tiki, Q1"),
            ExportRecord(date: TestClock.date(2026, 10, 7, 19), name: "=SUM(A1)", amount: 10_000, categoryTitle: "khác", isOutsideBudget: false, placeName: nil),
        ]
        let result = try run(CSVExporter.csv(records, calendar: calendar))
        #expect(result.rows == [
            ImportedExpense(date: TestClock.date(2026, 10, 5, 7), name: "phở", amount: 45_000, categoryKey: "food", isOutsideBudget: false, placeName: nil),
            ImportedExpense(date: TestClock.date(2026, 10, 6, 9), name: "tai nghe", amount: 1_200_000, categoryKey: "shopping", isOutsideBudget: true, placeName: "Tiki, Q1"),
            ImportedExpense(date: TestClock.date(2026, 10, 7, 19), name: "=SUM(A1)", amount: 10_000, categoryKey: "other", isOutsideBudget: false, placeName: nil),
        ])
        #expect(result.duplicates == 0 && result.skippedIncome == 0 && result.rejected.isEmpty)
        #expect(result.total == 1_255_000)
        #expect(result.firstDate == TestClock.date(2026, 10, 5, 7) && result.lastDate == TestClock.date(2026, 10, 7, 19))
    }

    @Test func matchesEnglishAndCustomCategoryNames() throws {
        let text = "Date,Description,Amount,Category\n2026-10-05,phở,45000,Food\n2026-10-05,vé,90000,Entertainment\n2026-10-05,leo núi,200000,Leo núi\n2026-10-05,x,1000,Lạ hoắc"
        let result = try run(text, options(custom: [.init(key: "custom-abc", name: "Leo núi")]))
        #expect(result.rows.map(\.categoryKey) == ["food", "fun", "custom-abc", "other"])
    }

    @Test func guessesTheCategoryFromTheNameWhenThereIsNoCategoryColumn() throws {
        let text = "Ngày,Nội dung,Số tiền\n05/10/2026,Grab đi làm,32000\n05/10/2026,Cơm tấm,55000\n05/10/2026,Quà bạn,300000"
        let result = try run(text, options(rules: ["qua ban": "shopping"]))
        #expect(result.rows.map(\.categoryKey) == ["transport", "food", "shopping"])
    }

    @Test func readsABankStatementWithDebitAndCreditColumns() throws {
        let text = """
        Sao kê tài khoản
        Từ ngày 01/10/2026 đến 09/10/2026
        Ngày giao dịch;Nội dung giao dịch;Ghi nợ;Ghi có;Số dư
        05/10/2026;THANH TOAN GRAB;32.000;;5.000.000
        06/10/2026;LUONG THANG 10;;15.000.000;20.000.000
        07/10/2026;CHUYEN KHOAN CHO MINH;200.000;;19.800.000
        """
        let result = try run(text)
        #expect(result.rows.map(\.name) == ["THANH TOAN GRAB", "CHUYEN KHOAN CHO MINH"])
        #expect(result.rows.map(\.amount) == [32_000, 200_000])
        #expect(result.skippedIncome == 1)
    }

    @Test func aSignedAmountColumnTreatsPositiveRowsAsIncome() throws {
        let text = "Date,Description,Amount\n2026-10-05,Grab,-32000\n2026-10-06,Lương,15000000\n2026-10-07,Phở,-45000"
        let result = try run(text)
        #expect(result.rows.map(\.amount) == [32_000, 45_000])
        #expect(result.skippedIncome == 1)
    }

    @Test func anAllPositiveAmountColumnIsAllExpenses() throws {
        let result = try run("Date,Name,Amount\n2026-10-05,a,1000\n2026-10-06,b,2000")
        #expect(result.rows.count == 2 && result.skippedIncome == 0)
    }

    @Test func reportsMissingColumns() {
        #expect(CSVImporter.importExpenses(from: "", options: options()) == .failure(.empty))
        #expect(CSVImporter.importExpenses(from: "Ngày,Tên\n05/10/2026,phở", options: options()) == .failure(.missingColumns(date: false, amount: true)))
        #expect(CSVImporter.importExpenses(from: "Tên,Số tiền\nphở,45000", options: options()) == .failure(.missingColumns(date: true, amount: false)))
        #expect(CSVImporter.importExpenses(from: "a,b\n1,2", options: options()) == .failure(.missingColumns(date: true, amount: true)))
    }

    @Test func keepsGoodRowsAndReportsTheBadOnes() throws {
        let text = """
        Ngày,Tên,Số tiền
        05/10/2026,phở,45000
        31/02/2026,lỗi ngày,1000
        06/10/2026,lỗi tiền,abc
        20/10/2026,tương lai,2000
        07/10/2026,cf,29000
        """
        let result = try run(text)
        #expect(result.rows.map(\.name) == ["phở", "cf"])
        #expect(result.rejected.map(\.line) == [3, 4, 5])
        #expect(result.rejected.map(\.reason) == [.badDate, .badAmount, .futureDate])
    }

    @Test func tomorrowIsStillAcceptedForTimeZoneSlack() throws {
        let result = try run("Ngày,Tên,Số tiền\n10/10/2026,phở,45000")
        #expect(result.rows.count == 1)
    }

    @Test func skipsRowsAlreadyOnTheDeviceAndCountsMultiples() throws {
        let text = "Ngày,Giờ,Tên,Số tiền\n05/10/2026,07:00,Phở,45000\n05/10/2026,07:00,phở,45000\n05/10/2026,07:00,cf,29000"
        let phở = ImportSignature(date: TestClock.date(2026, 10, 5, 7), name: "PHỞ", amount: 45_000)
        let once = try run(text, options(existing: [phở]))
        #expect(once.rows.map(\.name) == ["phở", "cf"])           // máy có một, tệp có hai: nhập một
        #expect(once.duplicates == 1)
        let twice = try run(text, options(existing: [phở, phở]))
        #expect(twice.rows.map(\.name) == ["cf"])
        #expect(twice.duplicates == 2)
    }

    @Test func aDifferentMinuteIsNotADuplicate() throws {
        let existing = ImportSignature(date: TestClock.date(2026, 10, 5, 7), name: "phở", amount: 45_000)
        let result = try run("Ngày,Giờ,Tên,Số tiền\n05/10/2026,07:01,phở,45000", options(existing: [existing]))
        #expect(result.rows.count == 1 && result.duplicates == 0)
    }

    @Test func outsideBudgetColumnUnderstandsCommonMarks() throws {
        let text = "Ngày,Tên,Số tiền,Ngoài ngân sách\n05/10/2026,a,1000,x\n05/10/2026,b,1000,\n05/10/2026,c,1000,không\n05/10/2026,d,1000,1"
        #expect(try run(text).rows.map(\.isOutsideBudget) == [true, false, false, true])
    }

    @Test func removesTheFormulaGuardApostropheTheExporterAdds() throws {
        let text = "Ngày,Tên,Số tiền,Nơi\n05/10/2026,'-phở,1000,'@quán\n05/10/2026,'abc,1000,"
        let result = try run(text)
        #expect(result.rows.map(\.name) == ["-phở", "'abc"])
        #expect(result.rows.map(\.placeName) == ["@quán", nil])
    }

    @Test func aNamelessRowStillImports() throws {
        let result = try run("Ngày,Số tiền\n05/10/2026,45000")
        #expect(result.rows.map(\.name) == [""])
    }

    @Test func existingSignaturesIgnoreAccentsCaseAndSeconds() {
        let a = ImportSignature(date: TestClock.date(2026, 10, 5, 7).addingTimeInterval(12), name: "Phở  Bò", amount: 1)
        let b = ImportSignature(date: TestClock.date(2026, 10, 5, 7), name: "pho bo", amount: 1)
        #expect(a == b)
    }
}

struct ImportTextTests {
    @Test func readsUTF8WithAndWithoutBOM() {
        let text = "Ngày,Tên\n05/10/2026,phở"
        #expect(ImportText.decode(Data(text.utf8)) == text)
        let withBOM = ImportText.decode(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))
        #expect(CSVParser.rows(from: withBOM ?? "") == [["Ngày", "Tên"], ["05/10/2026", "phở"]])
    }

    @Test func readsUTF16WithBOM() throws {
        let little = Data([0xFF, 0xFE]) + (try #require("a,b".data(using: .utf16LittleEndian)))
        let big = Data([0xFE, 0xFF]) + (try #require("a,b".data(using: .utf16BigEndian)))
        #expect(ImportText.decode(little) == "a,b")
        #expect(ImportText.decode(big) == "a,b")
    }

    @Test func fallsBackToWindows1252ForOldSpreadsheetFiles() {
        #expect(ImportText.decode(Data([0x63, 0x61, 0x66, 0xE9])) == "café")
    }

    @Test func emptyFileHasNoText() {
        #expect(ImportText.decode(Data()) == nil)
    }
}
