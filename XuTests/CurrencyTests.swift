import Foundation
import Testing
@testable import Xu

struct CurrencyTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now

    private func find(_ text: String) -> ForeignAmountParser.Match? {
        ForeignAmountParser.find(in: TextNormalizer.words(text))
    }

    private func amount(_ text: String) -> ForeignAmount? { find(text)?.amount }

    @Test func recognizesCodesNamesAndSymbols() {
        #expect(amount("20 usd") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("20usd") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("$20") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("20$") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("usd 20") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("usd20") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("20 đô") == ForeignAmount(currency: .usd, minor: 2_000))
        #expect(amount("5 euro") == ForeignAmount(currency: .eur, minor: 500))
        #expect(amount("€5") == ForeignAmount(currency: .eur, minor: 500))
        #expect(amount("1000 yên") == ForeignAmount(currency: .jpy, minor: 1_000))
        #expect(amount("£3") == ForeignAmount(currency: .gbp, minor: 300))
        #expect(amount("100 baht") == ForeignAmount(currency: .thb, minor: 10_000))
        #expect(amount("s$4") == ForeignAmount(currency: .sgd, minor: 400))
    }

    @Test func swallowsDollarWordPair() {
        let match = find("cơm 20 đô la")
        #expect(match?.range == 1..<4)
        #expect(match?.amount == ForeignAmount(currency: .usd, minor: 2_000))
    }

    @Test func readsDecimalsAndGrouping() {
        #expect(amount("12.5 usd")?.minor == 1_250)
        #expect(amount("12,50 eur")?.minor == 1_250)
        #expect(amount("1,234.56 usd")?.minor == 123_456)
        #expect(amount("1.234,56 eur")?.minor == 123_456)
        #expect(amount("1.000 yên")?.minor == 1_000)
        #expect(amount("1.000.000 won")?.minor == 1_000_000)
    }

    @Test func readsThousandsMultiplier() {
        #expect(amount("10k yên")?.minor == 10_000)
        #expect(amount("10kyên")?.minor == 10_000)
    }

    @Test func ignoresPlainDongAmounts() {
        #expect(find("phở 45k") == nil)
        #expect(find("1 củ 2") == nil)
        #expect(find("cơm 45.000") == nil)
        #expect(find("ăn tối với đô") == nil)
    }

    @Test func convertsAtDefaultAndCustomRates() {
        let twenty = ForeignAmount(currency: .usd, minor: 2_000)
        #expect(ExchangeRates.standard.vnd(for: twenty) == 508_000)
        let custom = ExchangeRates(overrides: [.usd: 26_000])
        #expect(custom.vnd(for: twenty) == 520_000)
        #expect(ExchangeRates.standard.vnd(for: ForeignAmount(currency: .jpy, minor: 1_000)) == 170_000)
        #expect(ExchangeRates.standard.vnd(for: ForeignAmount(currency: .usd, minor: 0)) == nil)
    }

    @Test func roundsToHundredDong() {
        let rates = ExchangeRates(overrides: [.usd: 25_333])
        #expect(rates.vnd(for: ForeignAmount(currency: .usd, minor: 100)) == 25_300)
    }

    @Test func ratesRoundTripThroughStorage() {
        let rates = ExchangeRates(overrides: [.usd: 25_500, .krw: Decimal(string: "18.5") ?? 0])
        #expect(ExchangeRates(stored: rates.stored) == rates)
        #expect(ExchangeRates(stored: ["xyz": "5", "usd": "-3", "eur": "abc"]).overrides.isEmpty)
    }

    @Test func parsesTypedRates() {
        #expect(ExchangeRates.parseRate("25.400") == 25_400)
        #expect(ExchangeRates.parseRate("25400") == 25_400)
        #expect(ExchangeRates.parseRate("18,5") == Decimal(string: "18.5"))
        #expect(ExchangeRates.parseRate("") == nil)
        #expect(ExchangeRates.parseRate("abc") == nil)
        #expect(ExchangeRates.parseRate("0") == nil)
    }

    @Test func displaysOriginalAmount() {
        #expect(ForeignAmount(currency: .usd, minor: 2_000).display() == "20 USD")
        #expect(ForeignAmount(currency: .eur, minor: 1_205).display() == "12,05 EUR")
        #expect(ForeignAmount(currency: .jpy, minor: 1_000_000).display() == "1.000.000 JPY")
    }

    // MARK: - Trong bộ tách

    private func parse(_ text: String, rates: ExchangeRates = .standard) -> [ParsedLine] {
        ExpenseParser(rates: rates).parse(text, rules: [:], dailyAllowance: 0, now: now, calendar: calendar)
    }

    @Test func parserConvertsForeignAmountAndKeepsOriginal() {
        guard case .expense(let parsed)? = parse("cơm 20 usd").first else { Issue.record("không ra khoản chi"); return }
        #expect(parsed.name == "cơm")
        #expect(parsed.amount == 508_000)
        #expect(parsed.foreign == ForeignAmount(currency: .usd, minor: 2_000))
    }

    @Test func parserUsesCustomRates() {
        guard case .expense(let parsed)? = parse("vé $10", rates: ExchangeRates(overrides: [.usd: 24_000])).first else { Issue.record("không ra khoản chi"); return }
        #expect(parsed.amount == 240_000)
        #expect(parsed.name == "vé")
    }

    @Test func parserStillReadsDongAndMixedLines() {
        let lines = parse("phở 45k, taxi 15 usd")
        #expect(lines.count == 2)
        guard case .expense(let first) = lines[0], case .expense(let second) = lines[1] else { Issue.record("sai kiểu"); return }
        #expect(first.amount == 45_000)
        #expect(first.foreign == nil)
        #expect(second.amount == 381_000)
    }

    @Test func parserSplitsForeignTotal() {
        guard case .expense(let parsed)? = parse("tiệc 100 usd chia 4").first else { Issue.record("không ra khoản chi"); return }
        #expect(parsed.originalAmount == 2_540_000)
        #expect(parsed.amount == 635_000)
        #expect(parsed.foreign?.minor == 10_000)
    }
}
