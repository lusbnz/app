import Foundation
import Testing
@testable import Xu

struct DuplicateDetectorTests {
    private let now = TestClock.now
    private let calendar = TestClock.calendar

    private func recorded(_ name: String = "phở", amount: Int = 45_000, secondsAgo: TimeInterval = 60, date: Date? = nil) -> RecentEntry {
        RecentEntry(name: name, amount: amount, date: date ?? now, createdAt: now.addingTimeInterval(-secondsAgo))
    }

    private func match(_ name: String = "phở", _ amount: Int = 45_000, date: Date? = nil, among recent: [RecentEntry]) -> RecentEntry? {
        DuplicateDetector.match(name: name, amount: amount, date: date ?? now, among: recent, now: now, calendar: calendar)
    }

    @Test func sameNameAndAmountWithinWindowMatches() {
        #expect(match(among: [recorded()]) != nil)
    }

    @Test func ignoresCaseAndAccents() {
        #expect(match("PHỞ", among: [recorded("pho")]) != nil)
    }

    @Test func differentAmountOrNameDoesNotMatch() {
        #expect(match(among: [recorded(amount: 50_000)]) == nil)
        #expect(match(among: [recorded("bún")]) == nil)
    }

    @Test func olderThanWindowDoesNotMatch() {
        #expect(match(among: [recorded(secondsAgo: DuplicateDetector.window + 1)]) == nil)
        #expect(match(among: [recorded(secondsAgo: DuplicateDetector.window)]) != nil)
    }

    @Test func futureCreationTimeIsIgnored() {
        #expect(match(among: [recorded(secondsAgo: -30)]) == nil)
    }

    @Test func differentSpendingDayDoesNotMatch() {
        let yesterday = TestClock.date(2026, 10, 8)
        #expect(match(date: yesterday, among: [recorded()]) == nil)
        #expect(match(date: yesterday, among: [recorded(date: yesterday)]) != nil)
    }

    @Test func picksTheMostRecentMatch() {
        let found = match(among: [recorded(secondsAgo: 200), recorded(secondsAgo: 20), recorded(secondsAgo: 100)])
        #expect(found?.createdAt == now.addingTimeInterval(-20))
    }

    @Test func emptyHistoryHasNoMatch() {
        #expect(match(among: []) == nil)
    }
}
