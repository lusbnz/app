import Foundation
import Testing
@testable import Xu

struct SpendingSnapshotTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func date(_ day: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private var snapshot: SpendingSnapshot {
        SpendingSnapshot.make(records: [
            SpendingRecord(name: "cf", amount: 29_000, categoryKey: "food", date: date(1)),
            SpendingRecord(name: "CF", amount: 35_000, categoryKey: "food", date: date(2)),
            SpendingRecord(name: "grab", amount: 32_000, categoryKey: "transport", date: date(2)),
            SpendingRecord(name: "tai nghe", amount: 1_200_000, categoryKey: "shopping", date: date(3), isOutsideBudget: true),
            SpendingRecord(name: "phở", amount: 45_000, categoryKey: "food", date: date(30, month: 9)),
        ], monthlyBudget: 9_000_000, now: date(8), calendar: calendar)
    }

    @Test func totalsOnlyCountThisMonthInBudget() {
        #expect(snapshot.spent == 96_000)
        #expect(snapshot.remaining == 8_904_000)
        #expect(snapshot.outsideBudgetTotal == 1_200_000)
    }

    @Test func categoriesSortedDescending() {
        #expect(snapshot.byCategory.map(\.key) == ["food", "transport"])
        #expect(snapshot.byCategory.first?.total == 64_000)
    }

    @Test func namesAreGroupedIgnoringCase() {
        let coffee = snapshot.byName.first { $0.key == "cf" }
        #expect(coffee?.count == 2)
        #expect(coffee?.total == 64_000)
        #expect(coffee?.average == 32_000)
        #expect(snapshot.byName.first?.key == "tai nghe")
    }

    @Test func daysAscending() {
        #expect(snapshot.byDay.map(\.total) == [29_000, 67_000])
    }
}

struct SpendingFactsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private var sheet: String {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        let records = (0..<8).map { _ in SpendingRecord(name: "cf", amount: 29_000, categoryKey: "food", date: day) }
            + [SpendingRecord(name: "grab", amount: 32_000, categoryKey: "transport", date: day)]
        let snapshot = SpendingSnapshot.make(records: records, monthlyBudget: 9_000_000, now: day, calendar: calendar)
        return SpendingFacts.sheet(snapshot, calendar: calendar) { $0 == "food" ? "ăn uống" : "đi lại" }
    }

    @Test func sheetCarriesPrecomputedFigures() {
        #expect(sheet.contains("Ngân sách tháng: 9tr"))
        #expect(sheet.contains("Đã tiêu tháng này: 264k"))
        #expect(sheet.contains("- cf: 232k cho 8 lần, trung bình 29k mỗi lần"))
        #expect(sheet.contains("- grab: 32k cho 1 lần"))
        #expect(sheet.contains("- ăn uống: 232k cho 8 lần"))
        #expect(sheet.contains("- ngày 8/10: 264k"))
    }

    @Test func acceptsAnswersThatOnlyQuoteTheSheet() {
        #expect(SpendingFacts.usesOnlyKnownNumbers("232k cho 8 lần, trung bình 29k mỗi lần.", sheet: sheet, question: "cf hết bao nhiêu?"))
        #expect(SpendingFacts.usesOnlyKnownNumbers("Nhẩm chưa có số liệu cho câu này.", sheet: sheet, question: "?"))
        #expect(SpendingFacts.usesOnlyKnownNumbers("Tháng 10 bạn tiêu 264k.", sheet: sheet, question: "tháng 10 tiêu bao nhiêu?"))
    }

    @Test func rejectsInventedOrComputedNumbers() {
        #expect(!SpendingFacts.usesOnlyKnownNumbers("Khoảng 250k cho cf.", sheet: sheet, question: "cf hết bao nhiêu?"))
        #expect(!SpendingFacts.usesOnlyKnownNumbers("cf và grab hết 296k.", sheet: sheet, question: "cf và grab?"))
        #expect(!SpendingFacts.usesOnlyKnownNumbers("232k cho 9 lần.", sheet: sheet, question: "cf?"))
    }
}
