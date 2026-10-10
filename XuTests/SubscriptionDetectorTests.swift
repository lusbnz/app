import Foundation
import Testing
@testable import Xu

struct SubscriptionDetectorTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now   // 9/10/2026

    private func record(_ name: String, _ amount: Int, _ month: Int, _ day: Int, year: Int = 2026, category: String = "fun") -> SpendingRecord {
        SpendingRecord(name: name, amount: amount, categoryKey: category, date: TestClock.date(year, month, day, 9))
    }

    private func detect(_ records: [SpendingRecord]) -> [DetectedSubscription] {
        SubscriptionDetector.detect(records: records, now: now, calendar: calendar)
    }

    @Test func aMonthlyChargeIsRecognizedWithItsSchedule() throws {
        let found = try #require(detect([
            record("Netflix", 260_000, 7, 5), record("Netflix", 260_000, 8, 5),
            record("Netflix", 260_000, 9, 5), record("Netflix", 260_000, 10, 5),
        ]).first)
        #expect(found.cadence == .monthly)
        #expect(found.occurrences == 4)
        #expect(found.amount == 260_000 && found.previousAmount == nil && found.priceChange == nil)
        #expect(found.dayOfMonth == 5)
        #expect(found.nextDate == TestClock.date(2026, 11, 5, 9))
        #expect(found.monthlyCost == 260_000)
        #expect(found.categoryKey == "fun")
    }

    @Test func aPriceRiseIsReportedFromTheLastTwoCharges() throws {
        let found = try #require(detect([
            record("netflix", 260_000, 7, 5), record("netflix", 260_000, 8, 5),
            record("netflix", 260_000, 9, 5), record("Netflix", 290_000, 10, 5),
        ]).first)
        #expect(found.amount == 290_000 && found.previousAmount == 260_000 && found.priceChange == 30_000)
        #expect(found.name == "Netflix")                              // tên lần gần nhất
    }

    @Test func aMissedMonthIsTolerated() {
        let found = detect([
            record("Spotify", 59_000, 6, 12), record("Spotify", 59_000, 7, 12),
            record("Spotify", 59_000, 9, 12),                          // bỏ tháng 8
        ])
        #expect(found.first?.cadence == .monthly)
    }

    @Test func twoMissedMonthsOrIrregularGapsAreNot() {
        #expect(detect([
            record("Spotify", 59_000, 3, 12), record("Spotify", 59_000, 4, 12),
            record("Spotify", 59_000, 7, 12), record("Spotify", 59_000, 9, 12),
        ]).isEmpty)
    }

    @Test func dailyCoffeeAndRandomMealsAreNotSubscriptions() {
        var records: [SpendingRecord] = []
        for day in 1...9 { records.append(record("cf", 29_000, 10, day, category: "food")) }
        records += [record("phở", 45_000, 9, 3), record("phở", 45_000, 9, 19), record("phở", 50_000, 10, 4)]
        #expect(detect(records).isEmpty)
    }

    @Test func aBillThatChangesEveryMonthIsNotASubscription() {
        #expect(detect([
            record("tiền điện", 320_000, 6, 8), record("tiền điện", 410_000, 7, 8),
            record("tiền điện", 380_000, 8, 8), record("tiền điện", 450_000, 9, 8),
        ]).isEmpty)
    }

    @Test func twoChargesAreNotEnoughForAMonthlyPattern() {
        #expect(detect([record("Netflix", 260_000, 9, 5), record("Netflix", 260_000, 10, 5)]).isEmpty)
    }

    @Test func aWeeklyChargeNeedsFourOccurrences() throws {
        let weekly = [record("gửi xe", 20_000, 9, 14), record("gửi xe", 20_000, 9, 21), record("gửi xe", 20_000, 9, 28), record("gửi xe", 20_000, 10, 5)]
        let found = try #require(detect(weekly).first)
        #expect(found.cadence == .weekly)
        #expect(found.weekday == 2)                                    // thứ Hai
        #expect(found.monthlyCost == 20_000 * 52 / 12)
        #expect(detect(Array(weekly.suffix(3))).isEmpty)
    }

    @Test func aYearlyChargeNeedsOnlyTwoOccurrences() throws {
        let found = try #require(detect([
            record("tên miền", 300_000, 3, 15, year: 2025), record("tên miền", 300_000, 3, 15),
        ]).first)
        #expect(found.cadence == .yearly)
        #expect(found.nextDate == TestClock.date(2027, 3, 15, 9))
        #expect(found.monthOfYear == 3 && found.dayOfMonth == 15)
        #expect(found.monthlyCost == 25_000)
    }

    @Test func aChargeThatStoppedLongAgoIsDropped() {
        #expect(detect([
            record("Netflix", 260_000, 3, 5), record("Netflix", 260_000, 4, 5),
            record("Netflix", 260_000, 5, 5), record("Netflix", 260_000, 6, 5),
        ]).isEmpty)                                                    // lần cuối 5/6, đã hơn 75 ngày
    }

    @Test func nameVariantsAreOneGroupAndSameDayDuplicatesCollapse() throws {
        let found = try #require(detect([
            record("Netflix", 260_000, 7, 5), record("NETFLIX ", 260_000, 8, 5),
            record("netflix", 260_000, 9, 5), record("netflix", 260_000, 9, 5), record("Netflix", 260_000, 10, 5),
        ]).first)
        #expect(found.occurrences == 4)
    }

    @Test func amountsThatSwingTooMuchAreNotStable() {
        #expect(detect([
            record("gym", 300_000, 7, 3), record("gym", 500_000, 8, 3), record("gym", 300_000, 9, 3), record("gym", 600_000, 10, 3),
        ]).isEmpty)
    }

    @Test func mostExpensiveComesFirst() {
        let found = detect([
            record("Spotify", 59_000, 7, 12), record("Spotify", 59_000, 8, 12), record("Spotify", 59_000, 9, 12),
            record("Netflix", 260_000, 7, 5), record("Netflix", 260_000, 8, 5), record("Netflix", 260_000, 9, 5), record("Netflix", 260_000, 10, 5),
        ])
        #expect(found.map(\.key) == ["netflix", "spotify"])
    }

    // MARK: - Tăng giá khi vừa ghi

    @Test func aNewHigherChargeOnTheCycleIsAPriceRise() throws {
        let history = [record("Netflix", 260_000, 7, 5), record("Netflix", 260_000, 8, 5), record("Netflix", 260_000, 9, 5)]
        let rise = try #require(SubscriptionDetector.priceIncrease(name: "netflix", amount: 290_000, date: TestClock.date(2026, 10, 5, 9), history: history, calendar: calendar))
        #expect(rise.from == 260_000 && rise.to == 290_000 && rise.name == "netflix")
    }

    @Test func theSamePriceALowerPriceOrAnUnrelatedNameIsNoWarning() {
        let history = [record("Netflix", 260_000, 7, 5), record("Netflix", 260_000, 8, 5), record("Netflix", 260_000, 9, 5)]
        let date = TestClock.date(2026, 10, 5, 9)
        #expect(SubscriptionDetector.priceIncrease(name: "Netflix", amount: 260_000, date: date, history: history, calendar: calendar) == nil)
        #expect(SubscriptionDetector.priceIncrease(name: "Netflix", amount: 240_000, date: date, history: history, calendar: calendar) == nil)
        #expect(SubscriptionDetector.priceIncrease(name: "Spotify", amount: 290_000, date: date, history: history, calendar: calendar) == nil)
        #expect(SubscriptionDetector.priceIncrease(name: "", amount: 290_000, date: date, history: history, calendar: calendar) == nil)
    }

    @Test func aHigherChargeOffTheCycleIsNoWarning() {
        let history = [record("Netflix", 260_000, 7, 5), record("Netflix", 260_000, 8, 5), record("Netflix", 260_000, 9, 5)]
        #expect(SubscriptionDetector.priceIncrease(name: "Netflix", amount: 290_000, date: TestClock.date(2026, 9, 20, 9), history: history, calendar: calendar) == nil)
    }

    // MARK: - Đã theo dõi

    @Test func trackedMeansASimilarRecurringNameExists() throws {
        let found = try #require(detect([
            record("Netflix", 260_000, 7, 5), record("Netflix", 260_000, 8, 5), record("Netflix", 260_000, 9, 5),
        ]).first)
        #expect(SubscriptionDetector.isTracked(found, by: ["netflix"]))
        #expect(SubscriptionDetector.isTracked(found, by: ["Tiền nhà", "NETFLIX gia đình"]))
        #expect(!SubscriptionDetector.isTracked(found, by: ["Tiền nhà", "Spotify"]))
        #expect(!SubscriptionDetector.isTracked(found, by: [""]))
    }
}
