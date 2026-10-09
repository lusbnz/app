import Testing
@testable import Xu

struct AmountParsingTests {
    private func amount(_ text: String) -> Int? {
        guard case .expense(let expense)? = ExpenseParser().parse(text, rules: [:], dailyAllowance: 0).first else {
            return nil
        }
        return expense.amount
    }

    @Test(arguments: [
        ("phở 45k", 45_000), ("phở 45K", 45_000), ("phở 45 k", 45_000), ("phở 45", 45_000),
        ("phở 45.000", 45_000), ("phở 45,000", 45_000), ("phở 45000", 45_000), ("phở 45000đ", 45_000),
        ("phở 45k5", 45_500),
        ("trà đá 5 nghìn", 5_000), ("trà đá 5 ngàn", 5_000), ("trà đá 5 ngan", 5_000),
        ("sách 1tr2", 1_200_000),
        ("sách 1tr", 1_000_000), ("sách 1 củ", 1_000_000),
        ("sách 1.5tr", 1_500_000), ("sách 1,5tr", 1_500_000),
        ("sách 2 triệu", 2_000_000), ("sach 2 trieu", 2_000_000),
        ("áo 5 lít", 500_000),
        ("áo 2 xị", 200_000),
        ("45k phở", 45_000), ("45 phở", 45_000),
        ("phở 1.250.000", 1_250_000), ("phở 45.5k", 45_500),
        ("phở 45k rưỡi", 45_500), ("phở 45 k rưỡi", 45_500), ("pho 45k ruoi", 45_500),
        ("sách 1 triệu rưỡi", 1_500_000), ("sách 2tr rưỡi", 2_500_000), ("sách 1 củ rưỡi", 1_500_000),
        ("trà 5 nghìn rưỡi", 5_500), ("áo 5 lít rưỡi", 550_000),
        ("sách 1 củ 2", 1_200_000), ("sách 1 triệu 2", 1_200_000), ("sách 1 triệu 250", 1_250_000),
        ("sách 1 củ 2 chia 4", 300_000), ("1 củ 2 sách", 1_200_000),
    ])
    func readsAmount(text: String, expected: Int) {
        #expect(amount(text) == expected)
    }

    @Test(arguments: ["phở", "7up", "ăn sáng"])
    func missingAmountIsNil(text: String) {
        #expect(amount(text) == nil)
    }

    @Test func prefersAmountWithUnit() {
        #expect(amount("bia 2 lon 60k") == 60_000)
        #expect(amount("7up 15") == 15_000)
    }

    @Test func trailingDigitsAfterMillionAreNotAlwaysDecimals() {
        // "2 cái" là số lượng, không phải 1,2 triệu.
        #expect(amount("bút 1 triệu 2 cái") == 1_000_000)
        // Đơn vị nghìn không nhận số lẻ rời: "45k 5" vẫn là 45k.
        #expect(amount("phở 45k 5") == 45_000)
    }

    @Test func accentedLookalikesAreNotUnits() {
        // "cũ" không phải "củ"
        #expect(amount("sách 2 cũ 50k") == 50_000)
    }
}

struct BudgetInputTests {
    @Test(arguments: [("9tr", 9_000_000), ("9", 9_000_000), ("9.000.000đ", 9_000_000), ("7,5tr", 7_500_000), ("12 triệu", 12_000_000)])
    func readsBudget(text: String, expected: Int) {
        #expect(BudgetInput.parse(text) == expected)
    }

    @Test func rejectsNonsense() {
        #expect(BudgetInput.parse("") == nil)
        #expect(BudgetInput.parse("nhiều") == nil)
    }
}
