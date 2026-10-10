import CoreGraphics
import Foundation
import Testing
@testable import Xu

@MainActor
struct YearReportPDFTests {
    private let calendar = TestClock.calendar

    private func sampleReport() -> YearReport {
        var records: [SpendingRecord] = []
        let names: [(String, Int, String, String?)] = [
            ("phở", 45_000, "food", "Phở Thìn"), ("cf", 29_000, "food", "Highlands"), ("grab", 32_000, "transport", nil),
            ("cơm tấm", 55_000, "food", "Cơm tấm Ba Ghiền"), ("đổ xăng", 80_000, "transport", "Petrolimex"),
            ("Netflix", 260_000, "fun", nil), ("tiền điện", 620_000, "bills", nil), ("thuốc", 150_000, "health", nil),
            ("áo", 350_000, "shopping", "Uniqlo"), ("leo núi", 400_000, "custom-abc", nil),
        ]
        for month in 1...10 {
            for (index, item) in names.enumerated() {
                let amount = item.1 + month * 3_000 * (index % 3)
                records.append(SpendingRecord(
                    name: item.0, amount: amount, categoryKey: item.2, date: TestClock.date(2026, month, 1 + index * 2),
                    placeName: item.3
                ))
            }
        }
        records.append(SpendingRecord(name: "tủ lạnh", amount: 9_000_000, categoryKey: "shopping", date: TestClock.date(2026, 6, 20), isOutsideBudget: true))
        records.append(SpendingRecord(name: "năm trước", amount: 20_000_000, categoryKey: "food", date: TestClock.date(2025, 3, 1)))
        return YearReport.make(records: records, year: 2026, now: TestClock.now, calendar: calendar)
    }

    @Test func writesATwoPageA4Document() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("year-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let titles = ["food": "ăn uống", "transport": "đi lại", "fun": "giải trí", "bills": "hóa đơn", "health": "sức khỏe", "shopping": "mua sắm", "custom-abc": "Leo núi"]
        let url = try YearReportPDF.write(sampleReport(), categoryTitles: titles, calendar: calendar, directory: directory)
        #expect(url.lastPathComponent == "pennyline-bao-cao-2026.pdf")

        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages == 2)
        let box = try #require(document.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == YearReportPDF.pageSize)
        let bytes = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(bytes > 2_000)

        // Để xem bằng mắt khi cần: TEST_RUNNER_PENNYLINE_PDF_OUT=/đường/dẫn.pdf xcodebuild ... test
        if let out = ProcessInfo.processInfo.environment["PENNYLINE_PDF_OUT"] {
            let target = URL(fileURLWithPath: out)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: url, to: target)
        }
    }

    @Test func anEmptyYearStillWritesAValidDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("year-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = YearReport.make(records: [], year: 2026, now: TestClock.now, calendar: calendar)
        let url = try YearReportPDF.write(report, categoryTitles: [:], calendar: calendar, directory: directory)
        #expect(CGPDFDocument(url as CFURL)?.numberOfPages == 2)
    }

    @Test func fileNameCarriesTheYear() {
        #expect(YearReportPDF.fileName(year: 2025) == "pennyline-bao-cao-2025.pdf")
    }
}
