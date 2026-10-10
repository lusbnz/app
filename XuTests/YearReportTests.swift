import Foundation
import Testing
@testable import Xu

struct YearReportTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now   // 9/10/2026

    private func record(
        _ name: String, _ amount: Int, _ category: String, _ month: Int, _ day: Int, year: Int = 2026,
        outside: Bool = false, place: String? = nil
    ) -> SpendingRecord {
        SpendingRecord(
            name: name, amount: amount, categoryKey: category, date: TestClock.date(year, month, day),
            isOutsideBudget: outside, placeName: place
        )
    }

    private func make(_ records: [SpendingRecord], year: Int = 2026) -> YearReport {
        YearReport.make(records: records, year: year, now: now, calendar: calendar)
    }

    @Test func totalsCountEveryExpenseOfTheYearIncludingOutsideBudget() {
        let report = make([
            record("phở", 45_000, "food", 3, 2), record("grab", 32_000, "transport", 3, 9),
            record("tủ lạnh", 9_000_000, "shopping", 6, 1, outside: true),
            record("năm trước", 1_000_000, "food", 5, 5, year: 2025), record("năm sau", 1_000, "food", 1, 1, year: 2027),
        ])
        #expect(report.total == 9_077_000)
        #expect(report.outsideBudgetTotal == 9_000_000)
        #expect(report.count == 3)
        #expect(report.year == 2026)
    }

    @Test func thereAreAlwaysTwelveMonths() {
        let report = make([record("a", 100, "food", 3, 2), record("b", 200, "food", 3, 20), record("c", 50, "food", 8, 1)])
        #expect(report.months.map(\.month) == Array(1...12))
        #expect(report.months[2].total == 300 && report.months[2].count == 2)
        #expect(report.months[7].total == 50)
        #expect(report.months[0].total == 0 && report.months[0].count == 0)
        #expect(report.busiestMonth == 3 && report.quietestMonth == 8)
    }

    @Test func theUnfinishedCurrentMonthIsNeverTheQuietest() {
        // Hôm nay 9/10: tháng 10 mới có một khoản nhỏ, nhưng tháng ít nhất phải là một tháng đã trọn.
        let report = make([record("a", 900_000, "food", 8, 2), record("b", 500_000, "food", 9, 2), record("c", 10_000, "food", 10, 2)])
        #expect(report.quietestMonth == 9)
        #expect(report.busiestMonth == 8)
        let onlyThisMonth = make([record("c", 10_000, "food", 10, 2)])
        #expect(onlyThisMonth.quietestMonth == nil && onlyThisMonth.busiestMonth == 10)
    }

    @Test func categoriesNamesAndPlacesAreRankedByTotal() {
        let report = make([
            record("Phở", 45_000, "food", 3, 2, place: "Phở Thìn"), record("phở", 50_000, "food", 4, 2, place: "phở thìn"),
            record("grab", 200_000, "transport", 4, 3), record("cf", 29_000, "food", 4, 4, place: "Highlands"),
        ])
        #expect(report.byCategory.map(\.key) == ["transport", "food"])
        #expect(report.byCategory.map(\.total) == [200_000, 124_000])
        #expect(report.topNames.map(\.key) == ["grab", "pho", "cf"])
        #expect(report.topNames[1].label == "phở" && report.topNames[1].count == 2)       // chữ của lần gần nhất
        #expect(report.topPlaces.map(\.total) == [95_000, 29_000])
        #expect(report.topPlaces.first?.label == "phở thìn")
        #expect(report.share(of: report.byCategory[0]) == 62)
    }

    @Test func topListsAreCapped() {
        let records = (1...15).map { record("khoản \($0)", $0 * 1_000, "food", 2, $0, place: "nơi \($0)") }
        let report = make(records)
        #expect(report.topNames.count == 10)
        #expect(report.topPlaces.count == 5)
        #expect(report.topNames.first?.total == 15_000)
    }

    @Test func largestExpenseAndActiveDays() {
        let report = make([
            record("phở", 45_000, "food", 3, 2), record("cf", 29_000, "food", 3, 2), record("tai nghe", 1_200_000, "shopping", 5, 9),
        ])
        #expect(report.largest?.name == "tai nghe")
        #expect(report.activeDays == 2)
    }

    @Test func aCurrentYearAveragesOverMonthsSinceTheFirstExpenseUntilNow() {
        // Khoản đầu tháng 7, hôm nay tháng 10: tính bốn tháng.
        let report = make([record("a", 400_000, "food", 7, 1), record("b", 400_000, "food", 9, 1)])
        #expect(report.isPartial)
        #expect(report.monthsCounted == 4)
        #expect(report.averagePerMonth == 200_000)
    }

    @Test func aPastYearAveragesUntilDecember() {
        let report = make([record("a", 900_000, "food", 4, 1, year: 2025)], year: 2025)
        #expect(!report.isPartial)
        #expect(report.monthsCounted == 9)
        #expect(report.averagePerMonth == 100_000)
    }

    @Test func theCurrentYearIgnoresFutureDatedExpensesAndComparesTheSameSpanOfLastYear() {
        let report = make([
            record("nay", 1_500_000, "food", 5, 1), record("tương lai", 999_000, "food", 12, 1),
            record("trước, trong đoạn", 1_000_000, "food", 5, 1, year: 2025),
            record("trước, sau ngày này", 5_000_000, "food", 11, 1, year: 2025),
        ])
        #expect(report.total == 1_500_000)
        #expect(report.previousTotal == 1_000_000)
        #expect(report.changePercent == 50)
    }

    @Test func aPastYearComparesWithTheWholeYearBefore() {
        let report = make([
            record("a", 800_000, "food", 5, 1, year: 2025), record("b", 600_000, "food", 11, 1, year: 2024),
            record("c", 400_000, "food", 2, 1, year: 2024),
        ], year: 2025)
        #expect(report.previousTotal == 1_000_000)
        #expect(report.changePercent == -20)
    }

    @Test func noPreviousYearMeansNothingToCompare() {
        let report = make([record("a", 800_000, "food", 5, 1)])
        #expect(report.previousTotal == nil && report.changePercent == nil)
    }

    @Test func anEmptyYearIsAllZeros() {
        let report = make([])
        #expect(report.total == 0 && report.count == 0 && report.monthsCounted == 0 && report.averagePerMonth == 0)
        #expect(report.busiestMonth == nil && report.quietestMonth == nil && report.largest == nil)
        #expect(report.byCategory.isEmpty && report.topNames.isEmpty && report.topPlaces.isEmpty)
        #expect(report.months.count == 12)
    }

    @Test func availableYearsAreNewestFirst() {
        let years = YearReport.availableYears(records: [
            record("a", 1, "food", 1, 1, year: 2024), record("b", 1, "food", 1, 1), record("c", 1, "food", 6, 1, year: 2024),
        ], calendar: calendar)
        #expect(years == [2026, 2024])
    }
}
