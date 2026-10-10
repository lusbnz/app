import Foundation
import Testing
@testable import Xu

struct CSVExporterTests {
    private let calendar = TestClock.calendar

    private func record(_ name: String, amount: Int = 45_000, hour: Int = 12, day: Int = 9, place: String? = nil, outside: Bool = false) -> ExportRecord {
        ExportRecord(date: TestClock.date(2026, 10, day, hour), name: name, amount: amount, categoryTitle: "ăn uống", isOutsideBudget: outside, placeName: place)
    }

    private func lines(_ records: [ExportRecord]) -> [String] {
        let csv = CSVExporter.csv(records, calendar: calendar)
        return csv.dropFirst().components(separatedBy: "\r\n").dropLast().map { String($0) }
    }

    @Test func emptyExportHasOnlyHeaderAndBOM() {
        let csv = CSVExporter.csv([], calendar: calendar)
        #expect(csv.hasPrefix("\u{FEFF}Ngày,Giờ,Tên"))
        #expect(lines([]).count == 1)
    }

    @Test func rowHasDateTimeAmountAndCategory() {
        let rows = lines([record("phở", hour: 7)])
        #expect(rows[1] == "2026-10-09,07:00,phở,45000,ăn uống,,")
    }

    @Test func sortsOldestFirst() {
        let rows = lines([record("sau", day: 9), record("trước", day: 3)])
        #expect(rows[1].contains("trước"))
        #expect(rows[2].contains("sau"))
    }

    @Test func quotesCommasQuotesAndNewlines() {
        #expect(CSVExporter.escape("cơm, canh") == "\"cơm, canh\"")
        #expect(CSVExporter.escape("bún \"ngon\"") == "\"bún \"\"ngon\"\"\"")
        #expect(CSVExporter.escape("a\nb") == "\"a\nb\"")
        #expect(CSVExporter.escape("phở") == "phở")
    }

    @Test func neutralizesSpreadsheetFormulas() {
        #expect(CSVExporter.escape("=SUM(A1)") == "'=SUM(A1)")
        #expect(CSVExporter.escape("@abc") == "'@abc")
    }

    @Test func flagsOutsideBudgetAndPlace() {
        let rows = lines([record("xe", amount: 20_000_000, place: "Honda, Q1", outside: true)])
        #expect(rows[1].hasSuffix(",20000000,ăn uống,x,\"Honda, Q1\""))
    }

    @Test func fileNameUsesLocalDate() {
        #expect(CSVExporter.fileName(now: TestClock.date(2026, 10, 10), calendar: calendar) == "xu-chi-tieu-2026-10-10.csv")
    }
}
