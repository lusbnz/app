import Testing
@testable import Xu

struct MoneyFormatterTests {
    @Test(arguments: [
        (194_000, "194k"), (45_500, "46k"), (5_000, "5k"), (0, "0k"), (400, "0k"),
        (999_400, "999k"), (999_600, "1tr"), (1_000_000, "1tr"),
        (7_100_000, "7,1tr"), (9_000_000, "9tr"), (1_640_000, "1,6tr"), (1_950_000, "2tr"),
        (-56_000, "-56k"), (-1_200_000, "-1,2tr"),
    ])
    func short(amount: Int, expected: String) {
        #expect(MoneyFormatter.short(amount) == expected)
    }

    @Test func full() {
        #expect(MoneyFormatter.full(9_000_000) == "9.000.000đ")
        #expect(MoneyFormatter.full(45_000) == "45.000đ")
        #expect(MoneyFormatter.full(500) == "500đ")
    }

    @Test func spoken() {
        #expect(MoneyFormatter.spoken(194_000) == "194.000 đồng")
        #expect(MoneyFormatter.spoken(-56_000) == "âm 56.000 đồng")
    }
}
