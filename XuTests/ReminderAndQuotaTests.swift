import Foundation
import Testing
@testable import Xu

struct ReminderPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func remindsTonightWhenNothingLogged() {
        let dates = ReminderPlanner.fireDates(now: date(8, hour: 12), hasLoggedToday: false, days: 3, calendar: calendar)
        #expect(dates == [date(8, hour: 21), date(9, hour: 21), date(10, hour: 21)])
    }

    @Test func skipsTonightOnceSomethingIsLogged() {
        let dates = ReminderPlanner.fireDates(now: date(8, hour: 12), hasLoggedToday: true, days: 3, calendar: calendar)
        #expect(dates == [date(9, hour: 21), date(10, hour: 21)])
    }

    @Test func skipsTonightAfterNine() {
        let dates = ReminderPlanner.fireDates(now: date(8, hour: 22), hasLoggedToday: false, days: 2, calendar: calendar)
        #expect(dates == [date(9, hour: 21)])
    }
}

struct SaveQuotaTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    @Test func fiveSavesADay() {
        var quota = SaveQuota(day: "", count: 0)
        for _ in 0..<5 {
            #expect(quota.canSave(on: date(8), calendar: calendar))
            quota = quota.adding(1, on: date(8), calendar: calendar)
        }
        #expect(!quota.canSave(on: date(8), calendar: calendar))
        #expect(quota.used(on: date(8), calendar: calendar) == 5)
    }

    @Test func resetsTheNextDay() {
        let quota = SaveQuota(day: SaveQuota.dayKey(date(8), calendar: calendar), count: 5)
        #expect(quota.canSave(on: date(9), calendar: calendar))
        #expect(quota.adding(1, on: date(9), calendar: calendar).count == 1)
    }

    @Test func undoGivesOneBack() {
        let quota = SaveQuota(day: SaveQuota.dayKey(date(8), calendar: calendar), count: 5)
        #expect(quota.adding(-1, on: date(8), calendar: calendar).canSave(on: date(8), calendar: calendar))
        #expect(SaveQuota(day: "", count: 0).adding(-1, on: date(8), calendar: calendar).count == 0)
    }
}

struct LeaveReminderPolicyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private let place = FamiliarPlace(
        center: Coordinate(latitude: 10.7769, longitude: 106.7009), visits: 4,
        lastVisit: Date(timeIntervalSince1970: 0), usual: Suggestion(name: "phở", amount: 45_000, categoryKey: "food")
    )

    @Test func message() {
        #expect(LeaveReminderPolicy.message(for: place) == "Vừa rời quán phở quen. Ghi phở 45k như mọi lần?")
    }

    @Test func oncePerPlacePerDay() {
        var last: [String: String] = [:]
        #expect(LeaveReminderPolicy.shouldNotify(place: place, lastNotified: last, records: [], now: date(8), calendar: calendar))
        last = LeaveReminderPolicy.marking(place.id, in: last, now: date(8), calendar: calendar)
        #expect(!LeaveReminderPolicy.shouldNotify(place: place, lastNotified: last, records: [], now: date(8, hour: 19), calendar: calendar))
        #expect(LeaveReminderPolicy.shouldNotify(place: place, lastNotified: last, records: [], now: date(9), calendar: calendar))
    }

    @Test func markingDropsOlderDays() {
        let old = ["a": SaveQuota.dayKey(date(7), calendar: calendar)]
        let marked = LeaveReminderPolicy.marking("b", in: old, now: date(8), calendar: calendar)
        #expect(marked == ["b": SaveQuota.dayKey(date(8), calendar: calendar)])
    }

    @Test func silentWhenTheUsualIsAlreadyLoggedToday() {
        let logged = [SuggestionRecord(name: "Phở", amount: 45_000, categoryKey: "food", date: date(8, hour: 7))]
        #expect(!LeaveReminderPolicy.shouldNotify(place: place, lastNotified: [:], records: logged, now: date(8), calendar: calendar))
        let other = [SuggestionRecord(name: "phở", amount: 60_000, categoryKey: "food", date: date(8, hour: 7))]
        #expect(LeaveReminderPolicy.shouldNotify(place: place, lastNotified: [:], records: other, now: date(8), calendar: calendar))
    }
}
