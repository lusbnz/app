import Foundation
import Testing
@testable import Xu

struct WalletBalancesTests {
    private let cash = UUID()
    private let bank = UUID()
    private let start = TestClock.date(2026, 10, 1, 0)

    private func wallet(_ id: UUID, opening: Int, since: Date? = nil) -> WalletSnapshot {
        WalletSnapshot(id: id, openingBalance: opening, startDate: since ?? start)
    }

    private func move(_ id: UUID, _ delta: Int, day: Int) -> WalletMovement {
        WalletMovement(walletID: id, delta: delta, date: TestClock.date(2026, 10, day))
    }

    @Test func balanceIsOpeningPlusMovements() {
        let result = WalletBalances.balances(
            wallets: [wallet(cash, opening: 1_000_000), wallet(bank, opening: 5_000_000)],
            movements: [move(cash, -45_000, day: 3), move(cash, -55_000, day: 4), move(bank, 2_000_000, day: 5)]
        )
        #expect(result[cash] == 900_000)
        #expect(result[bank] == 7_000_000)
    }

    @Test func movementsBeforeTheStartDateAreAlreadyInTheOpeningBalance() {
        let result = WalletBalances.balances(
            wallets: [wallet(cash, opening: 1_000_000, since: TestClock.date(2026, 10, 5, 0))],
            movements: [move(cash, -100_000, day: 3), move(cash, -20_000, day: 5), move(cash, -30_000, day: 8)]
        )
        #expect(result[cash] == 950_000)
    }

    @Test func movementsOfUnknownWalletsAreIgnored() {
        let result = WalletBalances.balances(wallets: [wallet(cash, opening: 100)], movements: [move(UUID(), -50, day: 3)])
        #expect(result == [cash: 100])
    }

    @Test func aCreditCardCanGoNegative() {
        let result = WalletBalances.balances(wallets: [wallet(bank, opening: 0)], movements: [move(bank, -3_000_000, day: 2)])
        #expect(result[bank] == -3_000_000)
    }

    @Test func transferBetweenWalletsMovesMoneyOut_AndIn() {
        let transfer = WalletTransferRecord(from: bank, to: cash, amount: 500_000, date: TestClock.date(2026, 10, 6))
        #expect(transfer.isValid)
        let result = WalletBalances.balances(
            wallets: [wallet(cash, opening: 0), wallet(bank, opening: 2_000_000)], movements: transfer.movements
        )
        #expect(result[cash] == 500_000)
        #expect(result[bank] == 1_500_000)
    }

    @Test func incomeAndWithdrawalHaveOneSide() {
        let income = WalletTransferRecord(from: nil, to: bank, amount: 15_000_000, date: TestClock.date(2026, 10, 7))
        let withdrawal = WalletTransferRecord(from: bank, to: nil, amount: 1_000_000, date: TestClock.date(2026, 10, 8))
        #expect(income.isValid && withdrawal.isValid)
        #expect(income.movements == [WalletMovement(walletID: bank, delta: 15_000_000, date: income.date)])
        #expect(withdrawal.movements == [WalletMovement(walletID: bank, delta: -1_000_000, date: withdrawal.date)])
    }

    @Test func invalidTransfers() {
        let date = TestClock.now
        #expect(!WalletTransferRecord(from: cash, to: cash, amount: 100, date: date).isValid)
        #expect(!WalletTransferRecord(from: nil, to: nil, amount: 100, date: date).isValid)
        #expect(!WalletTransferRecord(from: cash, to: bank, amount: 0, date: date).isValid)
        #expect(!WalletTransferRecord(from: cash, to: bank, amount: -5, date: date).isValid)
    }

    @Test func signedAmountsAcceptANegativePrefix() {
        #expect(WalletBalances.signedAmount(from: "2tr") == 2_000_000)
        #expect(WalletBalances.signedAmount(from: "-500k") == -500_000)
        #expect(WalletBalances.signedAmount(from: " −1 triệu rưỡi ") == -1_500_000)
        #expect(WalletBalances.signedAmount(from: "") == nil)
        #expect(WalletBalances.signedAmount(from: "abc") == nil)
    }

    @Test func messageMatchesTheWalletWithTheLongestKeyword() {
        let a = UUID(), b = UUID(), c = UUID()
        let keywords: [(id: UUID, keywords: String)] = [
            (a, "vcb, vietcombank"), (b, "Techcombank\nTCB"), (c, "VCB 1234"),
        ]
        #expect(WalletBalances.wallet(matching: "VCB Digibank: TK 0011 -45,000VND", keywords: keywords) == a)
        #expect(WalletBalances.wallet(matching: "Vietcombank thong bao", keywords: keywords) == a)
        #expect(WalletBalances.wallet(matching: "TCB: TK +1,000,000 VND", keywords: keywords) == b)
        // Từ khóa dài hơn ("vcb 1234") thắng khi cả hai cùng khớp.
        #expect(WalletBalances.wallet(matching: "VCB 1234 -50,000VND", keywords: keywords) == c)
        #expect(WalletBalances.wallet(matching: "BIDV: TK -10,000VND", keywords: keywords) == nil)
        #expect(WalletBalances.wallet(matching: "anything", keywords: [(a, "")]) == nil)
        #expect(WalletBalances.wallet(matching: "x", keywords: [(a, "x")]) == nil)          // từ khóa một chữ quá ngắn, dễ khớp nhầm
    }
}
