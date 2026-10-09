import Foundation
import SwiftData
import Testing
@testable import Xu

/// Thứ sáu 9/10/2026, 15:00, giờ Việt Nam.
enum TestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        return calendar
    }()

    static let now = date(2026, 10, 9, 15)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }
}

struct DateHintTests {
    private func hint(_ text: String) -> DateHint.Result {
        DateHint.extract(from: TextNormalizer.words(text), now: TestClock.now, calendar: TestClock.calendar)
    }

    @Test(arguments: [
        ("phở hôm qua 45k", TestClock.date(2026, 10, 8)),
        ("hôm qua phở 45k", TestClock.date(2026, 10, 8)),
        ("phở hom qua 45k", TestClock.date(2026, 10, 8)),
        ("grab hôm kia 32k", TestClock.date(2026, 10, 7)),
        ("tối qua nhậu 200k", TestClock.date(2026, 10, 8, 19)),
        ("nhậu tối hôm qua 200k", TestClock.date(2026, 10, 8, 19)),
        ("nhậu hôm qua tối 200k", TestClock.date(2026, 10, 8, 19)),
        ("sáng nay cf 29", TestClock.date(2026, 10, 9, 8)),
        ("trưa nay cơm 50k", TestClock.date(2026, 10, 9, 12)),
        ("3 ngày trước áo 300k", TestClock.date(2026, 10, 6)),
        ("ba ngày trước áo 300k", TestClock.date(2026, 10, 6)),
    ])
    func relativeDates(text: String, expected: Date) {
        #expect(hint(text).date == expected)
    }

    @Test func removesTheHintFromTokens() {
        #expect(hint("phở hôm qua 45k").tokens == ["phở", "45k"])
        #expect(hint("tối qua nhậu 200k").tokens == ["nhậu", "200k"])
        #expect(hint("nhậu tối hôm qua 200k").tokens == ["nhậu", "200k"])
    }

    @Test func laterTodayIsClampedToNow() {
        // 15:00 hôm nay mà nói "tối nay" thì không được ghi vào 19:00.
        #expect(hint("tối nay phở 45k").date == TestClock.now)
    }

    @Test func todayHasNoDate() {
        #expect(hint("hôm nay phở 45k").date == nil)
        #expect(hint("hôm nay phở 45k").tokens == ["phở", "45k"])
    }

    @Test(arguments: [
        ("thứ 4 phở 45k", TestClock.date(2026, 10, 7)),
        ("thứ tư phở 45k", TestClock.date(2026, 10, 7)),
        ("thứ 2 phở 45k", TestClock.date(2026, 10, 5)),
        ("thứ bảy phở 45k", TestClock.date(2026, 10, 3)),
        ("chủ nhật phở 45k", TestClock.date(2026, 10, 4)),
        ("chu nhat pho 45k", TestClock.date(2026, 10, 4)),
    ])
    func weekdays(text: String, expected: Date) {
        #expect(hint(text).date == expected)
    }

    @Test func sameWeekdayAsTodayMeansToday() {
        #expect(hint("thứ 6 phở 45k").date == nil)
        #expect(hint("thứ 6 phở 45k").tokens == ["phở", "45k"])
    }

    @Test(arguments: [
        ("ngày 5 phở 45k", TestClock.date(2026, 10, 5)),
        ("ngày 9 phở 45k", TestClock.date(2026, 10, 9)),
        ("ngày 12 phở 45k", TestClock.date(2026, 9, 12)),
        ("ngày 5/10 phở 45k", TestClock.date(2026, 10, 5)),
        ("ngày 5 tháng 10 phở 45k", TestClock.date(2026, 10, 5)),
        ("ngày 20/12 phở 45k", TestClock.date(2025, 12, 20)),
    ])
    func dayOfMonth(text: String, expected: Date) {
        #expect(hint(text).date == expected)
    }

    @Test func impossibleDateIsIgnored() {
        // Tháng 9 không có ngày 31: giữ nguyên câu, không đoán.
        let result = hint("ngày 31 phở 45k")
        #expect(result.date == nil)
        #expect(result.tokens == ["ngày", "31", "phở", "45k"])
    }

    @Test(arguments: ["phở 45k", "cơm tấm 55", "nhậu 460k chia 4", "mua quà ngày lễ 100k"])
    func ordinaryTextIsUntouched(text: String) {
        let result = hint(text)
        #expect(result.date == nil)
        #expect(result.tokens == TextNormalizer.words(text))
    }
}

struct ParserDateTests {
    private func expense(_ text: String) -> ParsedExpense? {
        let lines = ExpenseParser().parse(text, rules: [:], dailyAllowance: 300_000, now: TestClock.now, calendar: TestClock.calendar)
        if case .expense(let expense)? = lines.first { return expense }
        return nil
    }

    @Test func pastDateDoesNotLeakIntoNameOrAmount() {
        let parsed = expense("phở hôm qua 45k")
        #expect(parsed?.name == "phở")
        #expect(parsed?.amount == 45_000)
        #expect(parsed?.date == TestClock.date(2026, 10, 8))
    }

    @Test func dayNumberIsNotTakenAsAmount() {
        let parsed = expense("ngày 5 phở 45k")
        #expect(parsed?.amount == 45_000)
        #expect(parsed?.date == TestClock.date(2026, 10, 5))
    }

    @Test func weekdayNumberIsNotTakenAsAmount() {
        let parsed = expense("grab thứ 4 32k")
        #expect(parsed?.name == "grab")
        #expect(parsed?.amount == 32_000)
    }

    @Test func eachItemKeepsItsOwnDate() {
        let lines = ExpenseParser().parse(
            "phở hôm qua 45k, cf 29", rules: [:], dailyAllowance: 0, now: TestClock.now, calendar: TestClock.calendar
        )
        let dates = lines.compactMap { line -> Date?? in
            if case .expense(let expense) = line { .some(expense.date) } else { nil }
        }
        #expect(dates == [TestClock.date(2026, 10, 8), nil])
    }

    @Test func splitAndPastDateTogether() {
        let parsed = expense("nhậu tối qua 460k chia 4")
        #expect(parsed?.splitCount == 4)
        #expect(parsed?.amount == 115_000)
        #expect(parsed?.date == TestClock.date(2026, 10, 8, 19))
    }
}

@MainActor
struct PastDateRecordingTests {
    @Test func recordedExpenseUsesSpokenDate() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)

        let batch = recorder.record(text: "phở hôm qua 45k", monthlyBudget: 9_000_000, now: TestClock.now, calendar: TestClock.calendar)
        #expect(batch != nil)
        let saved = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(saved.count == 1)
        #expect(saved.first?.date == TestClock.date(2026, 10, 8))
        #expect(saved.first?.name == "phở")
    }

    @Test func expenseWithoutDateUsesNow() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)

        recorder.record(text: "phở 45k", monthlyBudget: 9_000_000, now: TestClock.now, calendar: TestClock.calendar)
        let saved = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(saved.first?.date == TestClock.now)
    }
}
