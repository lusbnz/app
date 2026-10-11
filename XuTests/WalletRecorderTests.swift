import Foundation
import SwiftData
import Testing
@testable import Xu

@MainActor
struct WalletRecorderTests {
    private let calendar = TestClock.calendar
    private let created = TestClock.date(2026, 10, 1)

    private func makeRecorder() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "wallet-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    @Test func balanceIsOpeningPlusEverythingSinceTheWalletStarted() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let cash = recorder.addWallet(name: "Tiền mặt", kind: .cash, openingBalance: 1_000_000, keywords: "", now: created)
        let bank = recorder.addWallet(name: "VCB", kind: .bank, openingBalance: 5_000_000, keywords: "vcb", now: created)

        let spent = Expense(name: "phở", amount: 45_000, categoryKey: "food", date: TestClock.date(2026, 10, 5))
        spent.walletID = cash.id
        context.insert(spent)
        let before = Expense(name: "cũ", amount: 999_000, categoryKey: "food", date: TestClock.date(2026, 9, 20))
        before.walletID = cash.id                                   // trước ngày tạo ví: đã nằm trong số dư ban đầu
        context.insert(before)
        context.insert(Expense(name: "không ví", amount: 70_000, categoryKey: "food", date: TestClock.date(2026, 10, 5)))
        let lent = Loan(person: "Minh", amount: 200_000, date: TestClock.date(2026, 10, 6))
        lent.walletID = cash.id
        context.insert(lent)
        let repaid = Loan(person: "Lan", amount: 300_000, date: TestClock.date(2026, 10, 6))
        repaid.walletID = cash.id
        repaid.isRepaid = true
        context.insert(repaid)
        try context.save()
        recorder.addTransfer(from: bank.id, to: cash.id, amount: 500_000, date: TestClock.date(2026, 10, 7))
        recorder.addTransfer(from: nil, to: bank.id, amount: 15_000_000, date: TestClock.date(2026, 10, 8), note: "lương")

        let balances = recorder.walletBalances()
        #expect(balances[cash.id] == 1_000_000 - 45_000 - 200_000 + 500_000)
        #expect(balances[bank.id] == 5_000_000 - 500_000 + 15_000_000)
    }

    @Test func invalidTransfersAreRefused() {
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let cash = recorder.addWallet(name: "Tiền mặt", kind: .cash, openingBalance: 0, keywords: "", now: created)
        #expect(recorder.addTransfer(from: cash.id, to: cash.id, amount: 1_000, date: created) == nil)
        #expect(recorder.addTransfer(from: nil, to: nil, amount: 1_000, date: created) == nil)
        #expect(recorder.addTransfer(from: cash.id, to: nil, amount: 0, date: created) == nil)
        #expect(recorder.addTransfer(from: cash.id, to: nil, amount: 1_000, date: created) != nil)
    }

    @Test func deletingAWalletKeepsItsExpensesAndDropsOrphanTransfers() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let cash = recorder.addWallet(name: "Tiền mặt", kind: .cash, openingBalance: 0, keywords: "", now: created)
        let bank = recorder.addWallet(name: "VCB", kind: .bank, openingBalance: 0, keywords: "", now: created)
        let spent = Expense(name: "phở", amount: 45_000, categoryKey: "food", date: created)
        spent.walletID = cash.id
        context.insert(spent)
        recorder.addTransfer(from: nil, to: cash.id, amount: 100_000, date: created)          // chỉ có ví này: sẽ bị xóa
        recorder.addTransfer(from: cash.id, to: bank.id, amount: 50_000, date: created)       // còn đầu kia: giữ lại

        recorder.deleteWallet(cash)
        #expect(try context.fetch(FetchDescriptor<Expense>()).map(\.walletID) == [nil])
        let transfers = try context.fetch(FetchDescriptor<WalletTransfer>())
        #expect(transfers.count == 1)
        #expect(transfers.first?.fromID == nil && transfers.first?.toID == bank.id)
        #expect(recorder.wallets().map(\.name) == ["VCB"])
    }

    @Test func recordingWithAWalletTagsExpensesAndLoans() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let cash = recorder.addWallet(name: "Tiền mặt", kind: .cash, openingBalance: 0, keywords: "", now: created)
        recorder.record(
            [.expense(ExpenseDraft(name: "phở", amount: 45_000, categoryKey: "food")), .loan(person: "Minh", amount: 200_000)],
            in: RecordContext(walletID: cash.id)
        )
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.walletID == cash.id)
        #expect(try context.fetch(FetchDescriptor<Loan>()).first?.walletID == cash.id)
    }

    // MARK: - Tin nhắn ngân hàng

    @Test func aDebitMessageBecomesAnExpenseOnTheMatchingWallet() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        _ = recorder.addWallet(name: "Tiền mặt", kind: .cash, openingBalance: 0, keywords: "", now: created)
        let bank = recorder.addWallet(name: "VCB", kind: .bank, openingBalance: 0, keywords: "vietcombank, vcb", now: created)

        let message = "Vietcombank: TK 0011 -45,000VND luc 09/10/2026 08:15. SD 12,345,678VND. ND: Highlands Coffee"
        let result = recorder.recordBankMessage(message, budget: .monthly(9_000_000), now: TestClock.now, calendar: calendar, defaults: defaults)
        guard case .expense = result else {
            Issue.record("mong đợi một khoản chi, nhận \(result)")
            return
        }
        let expense = try #require(context.fetch(FetchDescriptor<Expense>()).first)
        #expect(expense.amount == 45_000)
        #expect(expense.walletID == bank.id)
        #expect(expense.rawText == message)
        #expect(calendar.component(.day, from: expense.date) == 9)

        // Phím tắt chạy lại cùng tin nhắn: không ghi lần hai.
        #expect(recorder.recordBankMessage(message, budget: .monthly(9_000_000), now: TestClock.now, calendar: calendar, defaults: defaults) == .duplicate)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
    }

    @Test func aCreditMessageTopsUpTheMatchingWalletOrIsIgnored() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let message = "VCB: TK 0011 +15,000,000VND luc 09/10/2026 08:15. SD 20,000,000VND. ND: LUONG THANG 10"
        #expect(recorder.recordBankMessage(message, budget: .monthly(9_000_000), now: TestClock.now, calendar: calendar, defaults: defaults)
                == .incomeIgnored(amount: 15_000_000))

        let bank = recorder.addWallet(name: "VCB", kind: .bank, openingBalance: 0, keywords: "vcb", now: created)
        let other = "VCB: TK 0011 +2,000,000VND luc 09/10/2026 09:00. SD 22,000,000VND. ND: hoan tien"
        #expect(recorder.recordBankMessage(other, budget: .monthly(9_000_000), now: TestClock.now, calendar: calendar, defaults: defaults)
                == .income(amount: 2_000_000, walletName: "VCB"))
        #expect(recorder.walletBalances()[bank.id] == 2_000_000)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)      // tiền vào không phải khoản chi
    }

    @Test func textThatIsNotABankMessageIsUnreadableAndNotRemembered() {
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(recorder.recordBankMessage("chào bạn", budget: .monthly(9_000_000), now: TestClock.now, calendar: calendar, defaults: defaults) == .unreadable)
        #expect((defaults.stringArray(forKey: SettingsKey.bankMessages) ?? []).isEmpty)
    }

    @Test func fingerprintsIgnoreSpacingCaseAndAccents() {
        #expect(BankMessageLog.fingerprint("TK 0011 -45,000VND. ND: Phở") == BankMessageLog.fingerprint("tk0011 -45.000 vnd nd pho"))
        #expect(BankMessageLog.fingerprint("TK 0011 -45,000VND") != BankMessageLog.fingerprint("TK 0011 -46,000VND"))
    }
}
