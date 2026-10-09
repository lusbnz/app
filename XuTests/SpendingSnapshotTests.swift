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
