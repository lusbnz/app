import Foundation
import Testing
@testable import Xu

struct SuggestionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    /// 8/10/2026 là thứ 5.
    private func date(_ day: Int, hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: 15))!
    }

    private func record(_ name: String, _ amount: Int, day: Int, hour: Int, month: Int = 10, at coordinate: Coordinate? = nil) -> SuggestionRecord {
        SuggestionRecord(name: name, amount: amount, categoryKey: "food", date: date(day, hour: hour, month: month), coordinate: coordinate)
    }

    private let home = Coordinate(latitude: 10.7769, longitude: 106.7009)
    /// Khoảng 55 mét về phía bắc.
    private let nearHome = Coordinate(latitude: 10.7774, longitude: 106.7009)
    /// Khoảng 1,1 km về phía bắc.
    private let far = Coordinate(latitude: 10.7869, longitude: 106.7009)

    // MARK: Buổi

    @Test(arguments: [(5, PartOfDay.morning), (10, .morning), (11, .noon), (13, .noon), (14, .afternoon), (17, .afternoon), (18, .evening), (2, .evening)])
    func partOfDay(hour: Int, expected: PartOfDay) {
        #expect(PartOfDay.of(date(8, hour: hour), calendar: calendar) == expected)
    }

    // MARK: Theo giờ

    @Test func suggestsWhatIsUsuallyLoggedAtThisTimeOfDay() {
        let records = [
            record("cơm tấm", 55_000, day: 5, hour: 12), record("Cơm tấm", 55_000, day: 6, hour: 12),
            record("cơm tấm", 55_000, day: 7, hour: 12),
            record("phở", 45_000, day: 6, hour: 7), record("phở", 45_000, day: 7, hour: 7),
            record("bún", 40_000, day: 7, hour: 12),
        ]
        let noon = TimeSuggester.suggestions(records: records, now: date(8, hour: 12), calendar: calendar)
        #expect(noon.map(\.name) == ["cơm tấm"])
        let morning = TimeSuggester.suggestions(records: records, now: date(8, hour: 7), calendar: calendar)
        #expect(morning.map(\.name) == ["phở"])
    }

    @Test func sameWeekdayScoresHigher() {
        let records = [
            // thứ 5 tuần trước và tuần trước nữa
            record("bún chả", 60_000, day: 1, hour: 12), record("bún chả", 60_000, day: 24, hour: 12, month: 9),
            // ba ngày thường khác
            record("cơm tấm", 55_000, day: 5, hour: 12), record("cơm tấm", 55_000, day: 6, hour: 12),
            record("cơm tấm", 55_000, day: 7, hour: 12),
        ]
        let suggestions = TimeSuggester.suggestions(records: records, now: date(8, hour: 12), calendar: calendar)
        #expect(suggestions.map(\.name) == ["bún chả", "cơm tấm"])
    }

    @Test func skipsWhatWasLoggedToday() {
        let records = [
            record("cơm tấm", 55_000, day: 6, hour: 12), record("cơm tấm", 55_000, day: 7, hour: 12),
            record("cơm tấm", 55_000, day: 8, hour: 11),
        ]
        #expect(TimeSuggester.suggestions(records: records, now: date(8, hour: 12), calendar: calendar).isEmpty)
    }

    @Test func differentAmountIsADifferentSuggestion() {
        let records = [
            record("cf", 29_000, day: 6, hour: 9), record("cf", 29_000, day: 7, hour: 9), record("cf", 45_000, day: 5, hour: 9),
        ]
        let suggestions = TimeSuggester.suggestions(records: records, now: date(8, hour: 9), calendar: calendar)
        #expect(suggestions == [Suggestion(name: "cf", amount: 29_000, categoryKey: "food")])
    }

    @Test func ignoresOlderThanThirtyDays() {
        let records = [record("cf", 29_000, day: 1, hour: 9, month: 9), record("cf", 29_000, day: 2, hour: 9, month: 9)]
        #expect(TimeSuggester.suggestions(records: records, now: date(8, hour: 9), calendar: calendar).isEmpty)
    }

    @Test func limitsToThree() {
        let records = ["a", "b", "c", "d"].flatMap { name in
            [record(name, 10_000, day: 6, hour: 12), record(name, 10_000, day: 7, hour: 12)]
        }
        #expect(TimeSuggester.suggestions(records: records, now: date(8, hour: 12), calendar: calendar).count == 3)
    }

    // MARK: Theo vị trí

    @Test func distance() {
        #expect(abs(home.distance(to: nearHome) - 55.6) < 1)
        #expect(home.distance(to: far) > 1_000)
    }

    @Test func placeIsFamiliarFromTwoVisits() {
        let once = [record("phở", 45_000, day: 6, hour: 7, at: home)]
        #expect(PlaceSuggester.places(records: once).isEmpty)
        let twice = once + [record("phở", 45_000, day: 7, hour: 7, at: nearHome)]
        #expect(PlaceSuggester.places(records: twice).map(\.visits) == [2])
    }

    @Test func suggestsTheUsualNearAFamiliarPlace() {
        let records = [
            record("phở", 45_000, day: 5, hour: 7, at: home), record("phở", 45_000, day: 6, hour: 7, at: nearHome),
            record("trà đá", 5_000, day: 6, hour: 7, at: home),
            record("cơm", 55_000, day: 6, hour: 12, at: far), record("cơm", 55_000, day: 7, hour: 12, at: far),
        ]
        let result = PlaceSuggester.suggestion(near: nearHome, records: records, now: date(8, hour: 7), calendar: calendar)
        #expect(result?.suggestion.name == "phở")
        #expect(result?.place.label == "quán phở quen")
        let nowhere = Coordinate(latitude: 10.8, longitude: 106.8)
        #expect(PlaceSuggester.suggestion(near: nowhere, records: records, now: date(8, hour: 7), calendar: calendar) == nil)
    }

    @Test func placeSuggestionSkipsWhatWasLoggedToday() {
        let records = [
            record("phở", 45_000, day: 6, hour: 7, at: home), record("phở", 45_000, day: 7, hour: 7, at: home),
            record("phở", 45_000, day: 8, hour: 6, at: home),
        ]
        #expect(PlaceSuggester.suggestion(near: home, records: records, now: date(8, hour: 7), calendar: calendar) == nil)
    }

    @Test func monitorsOnlyPlacesWithThreeVisitsMostRecentFirstCappedAtTwenty() {
        var records: [SuggestionRecord] = []
        for index in 0..<25 {
            let place = Coordinate(latitude: 10.0 + Double(index) * 0.01, longitude: 106.7)
            for visit in 0..<3 {
                records.append(record("quán \(index)", 30_000, day: 1 + visit, hour: index % 24, at: place))
            }
        }
        records.append(record("ghé một lần", 30_000, day: 7, hour: 23, at: far))
        records.append(record("ghé một lần", 30_000, day: 7, hour: 22, at: far))
        let monitored = PlaceSuggester.monitoredPlaces(records: records)
        #expect(monitored.count == 20)
        #expect(monitored.allSatisfy { $0.visits >= 3 })
        #expect(monitored.first?.usual.name == "quán 23")
        #expect(monitored.map(\.lastVisit) == monitored.map(\.lastVisit).sorted(by: >))
    }
}
