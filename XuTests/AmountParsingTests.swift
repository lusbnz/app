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

    @Test func accentedLookalikesAreNotUnits() {
        // "cũ" không phải "củ"
        #expect(amount("sách 2 cũ 50k") == 50_000)
    }
}
