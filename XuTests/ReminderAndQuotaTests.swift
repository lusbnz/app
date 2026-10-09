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
