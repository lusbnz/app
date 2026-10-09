import Testing
@testable import Xu

struct ExpenseParserTests {
    private let parser = ExpenseParser()

    private func expenses(_ text: String, rules: [String: String] = [:], allowance: Int = 300_000) -> [ParsedExpense] {
        parser.parse(text, rules: rules, dailyAllowance: allowance).compactMap {
            if case .expense(let expense) = $0 { expense } else { nil }
        }
    }

    // MARK: Tên

    @Test func nameKeepsWhatWasTyped() {
        #expect(expenses("Phở bò 45k").first?.name == "Phở bò")
        #expect(expenses("45k phở").first?.name == "phở")
    }

    // MARK: Chia tiền

    @Test(arguments: ["nhậu 460k chia 4", "nhậu 460k chia4", "nhậu 460k /4", "nhậu 460k/4", "nhậu 460k chia 4 người"])
    func split(text: String) {
        let expense = expenses(text).first
        #expect(expense?.name == "nhậu")
        #expect(expense?.amount == 115_000)
        #expect(expense?.originalAmount == 460_000)
        #expect(expense?.splitCount == 4)
    }

    @Test func splitRoundsToThousand() {
        #expect(expenses("lẩu 500k chia 3").first?.amount == 167_000)
    }

    @Test func noSplitLeavesFieldsNil() {
        let expense = expenses("phở 45k").first
        #expect(expense?.originalAmount == nil)
        #expect(expense?.splitCount == nil)
    }

    // MARK: Ứng tiền

    @Test(arguments: ["ứng cho Minh 200k", "cho Minh mượn 200k", "ung cho Minh 200k", "cho Minh vay 200k"])
    func loan(text: String) {
        #expect(parser.parse(text, rules: [:], dailyAllowance: 300_000) == [.loan(person: "Minh", amount: 200_000)])
    }

    // MARK: Khoản lớn

    @Test func largeExpenseIsOutsideBudget() {
        #expect(expenses("tai nghe 1tr2").first?.isOutsideBudget == true)
        #expect(expenses("đổ xăng 80k").first?.isOutsideBudget == false)
        #expect(expenses("áo 900k").first?.isOutsideBudget == false)
        #expect(expenses("áo 901k").first?.isOutsideBudget == true)
    }

    @Test func noAllowanceMeansNothingIsOutside() {
        #expect(expenses("tai nghe 1tr2", allowance: 0).first?.isOutsideBudget == false)
    }

    // MARK: Câu hỏi

    @Test(arguments: [
        "tháng này cf hết bao nhiêu?", "tháng này cf hết bao nhiêu", "ăn phở mấy lần rồi",
        "thang nay cf het bao nhieu", "tuần này tiêu gì?",
    ])
    func question(text: String) {
        #expect(parser.parse(text, rules: [:], dailyAllowance: 300_000) == [.question(text)])
    }

    @Test func lookalikeIsNotQuestion() {
        #expect(expenses("sửa máy lạnh 300k").first?.amount == 300_000)
    }

    // MARK: Nhiều khoản

    @Test func multipleItems() {
        let parsed = expenses("cơm tấm 55, đổ xăng 80k, tai nghe 1tr2")
        #expect(parsed.map(\.name) == ["cơm tấm", "đổ xăng", "tai nghe"])
        #expect(parsed.map(\.amount) == [55_000, 80_000, 1_200_000])
        #expect(parsed.map(\.isOutsideBudget) == [false, false, true])
    }

    @Test(arguments: ["phở 45k; grab 32; cf 29", "phở 45k\ngrab 32\ncf 29", "phở 45k và grab 32 và cf 29", "phở 45k,grab 32,cf 29"])
    func separators(text: String) {
        #expect(expenses(text).map(\.amount) == [45_000, 32_000, 29_000])
    }

    @Test func andInsideNameDoesNotSplit() {
        let parsed = expenses("bánh và trà 50k")
        #expect(parsed.count == 1)
        #expect(parsed.first?.name == "bánh và trà")
    }

    @Test func mixedLines() {
        let parsed = parser.parse("phở 45k, ứng cho Minh 200k", rules: [:], dailyAllowance: 300_000)
        #expect(parsed.count == 2)
        #expect(parsed.last == .loan(person: "Minh", amount: 200_000))
    }

    // MARK: Phân loại

    @Test(arguments: [
        ("phở 45k", "food"), ("cf 29", "food"), ("cà phê 29", "food"), ("ca phe 29", "food"), ("nhậu 460k", "food"),
        ("grab 32", "transport"), ("be 20", "transport"), ("đổ xăng 80k", "transport"), ("gửi xe 5k", "transport"),
        ("tai nghe 1tr2", "shopping"), ("thuốc 50k", "health"), ("xem phim 90k", "fun"),
        ("quà cho bé 200k", "other"), ("linh tinh 10", "other"),
    ])
    func builtInCategory(text: String, expected: String) {
        #expect(expenses(text).first?.categoryKey == expected)
    }

    @Test func taughtRuleWins() {
        let rules = [TextNormalizer.keyword("Phở"): "fun", TextNormalizer.keyword("trà sữa"): "fun"]
        #expect(expenses("phở 45k", rules: rules).first?.categoryKey == "fun")
        #expect(expenses("trà sữa trân châu 45k", rules: rules).first?.categoryKey == "fun")
        #expect(expenses("trà đá 5k", rules: rules).first?.categoryKey == "food")
    }

    @Test func keywordNormalization() {
        #expect(TextNormalizer.keyword("  Cà   Phê Đá ") == "ca phe da")
    }
}
