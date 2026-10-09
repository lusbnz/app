import Testing
@testable import Xu

struct SpokenNumbersTests {
    @Test(arguments: [
        ("phở bốn mươi lăm nghìn", "phở 45000"),
        ("bún mười lăm nghìn", "bún 15000"),
        ("trà hai mươi nghìn", "trà 20000"),
        ("cơm hai trăm rưỡi", "cơm 250"),
        ("cơm hai trăm năm mươi", "cơm 250"),
        ("cơm hai trăm năm", "cơm 250"),
        ("áo một triệu rưỡi", "áo 1500000"),
        ("áo một triệu hai", "áo 1200000"),
        ("sách một triệu hai trăm", "sách 1200000"),
        ("sách một triệu hai trăm năm mươi", "sách 1250000"),
        ("tai nghe một triệu hai trăm nghìn", "tai nghe 1200000"),
        ("nước hai nghìn rưỡi", "nước 2500"),
        ("phòng một trăm lẻ năm nghìn", "phòng 105000"),
        ("phở năm mươi", "phở 50"),
        ("nhậu bốn trăm sáu mươi nghìn chia bốn", "nhậu 460000 chia bốn"),
        ("pho bon muoi lam nghin", "pho 45000"),
        ("phở bốn mươi lăm nghìn, grab ba mươi hai nghìn", "phở 45000, grab 32000"),
    ])
    func convertsSpokenAmounts(spoken: String, expected: String) {
        #expect(SpokenNumbers.normalize(spoken) == expected)
    }

    @Test(arguments: [
        "nhậu 460k chia ba", "đi chơi với ba mẹ", "năm ngoái 50k", "phở 45k", "một người", "chia năm", "nghìn", "triệu",
    ])
    func leavesOrdinaryTextAlone(text: String) {
        #expect(SpokenNumbers.normalize(text) == text)
    }

    @Test func rejectsInvalidSequences() {
        #expect(SpokenNumbers.normalize("hai ba trăm") == "hai ba trăm")
        #expect(SpokenNumbers.normalize("rưỡi") == "rưỡi")
        #expect(SpokenNumbers.normalize("nghìn nghìn") == "nghìn nghìn")
    }

    @Test func parserReadsNormalizedSpeech() {
        let parsed = ExpenseParser().parse(SpokenNumbers.normalize("phở bốn mươi lăm nghìn"), rules: [:], dailyAllowance: 0, now: TestClock.now, calendar: TestClock.calendar)
        guard case .expense(let expense)? = parsed.first else {
            Issue.record("không tách được khoản chi")
            return
        }
        #expect(expense.name == "phở")
        #expect(expense.amount == 45_000)
    }

    @Test func spokenSplitWithSpokenAmount() {
        let parsed = ExpenseParser().parse(SpokenNumbers.normalize("nhậu bốn trăm sáu mươi nghìn chia bốn"), rules: [:], dailyAllowance: 0, now: TestClock.now, calendar: TestClock.calendar)
        guard case .expense(let expense)? = parsed.first else {
            Issue.record("không tách được khoản chi")
            return
        }
        #expect(expense.originalAmount == 460_000)
        #expect(expense.splitCount == 4)
        #expect(expense.amount == 115_000)
    }
}
