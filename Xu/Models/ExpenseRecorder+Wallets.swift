import Foundation
import SwiftData

/// Ví, chuyển tiền và ghi từ tin nhắn ngân hàng.
extension ExpenseRecorder {
    // MARK: - Ví

    func wallets() -> [Wallet] {
        (try? context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    @discardableResult
    func addWallet(name: String, kind: WalletKind, openingBalance: Int, keywords: String, now: Date) -> Wallet {
        let wallet = Wallet(name: name, kind: kind, openingBalance: openingBalance, keywords: keywords, createdAt: now)
        context.insert(wallet)
        commit()
        return wallet
    }

    func updateWallet(_ wallet: Wallet, name: String, kind: WalletKind, openingBalance: Int, keywords: String) {
        wallet.name = name
        wallet.kind = kind
        wallet.openingBalance = openingBalance
        wallet.keywords = keywords
        commit()
    }

    /// Xóa ví: khoản chi và khoản ứng của ví vẫn còn (chỉ bỏ nối với ví), lần chuyển tiền mất đầu này; lần chuyển không còn ví nào thì xóa.
    func deleteWallet(_ wallet: Wallet) {
        let id = wallet.id
        for expense in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.walletID == id }))) ?? [] {
            expense.walletID = nil
        }
        for loan in (try? context.fetch(FetchDescriptor<Loan>(predicate: #Predicate { $0.walletID == id }))) ?? [] {
            loan.walletID = nil
        }
        for transfer in (try? context.fetch(FetchDescriptor<WalletTransfer>())) ?? [] {
            if transfer.fromID == id { transfer.fromID = nil }
            if transfer.toID == id { transfer.toID = nil }
            if transfer.fromID == nil, transfer.toID == nil { context.delete(transfer) }
        }
        context.delete(wallet)
        if Self.lastWalletID == id { Self.lastWalletID = nil }
        commit()
    }

    /// Chuyển tiền; nil khi không hợp lệ (số tiền không dương, không có ví nào, hoặc hai đầu là một ví).
    @discardableResult
    func addTransfer(from: UUID?, to: UUID?, amount: Int, date: Date, note: String = "") -> WalletTransfer? {
        guard WalletTransferRecord(from: from, to: to, amount: amount, date: date).isValid else { return nil }
        let transfer = WalletTransfer(fromID: from, toID: to, amount: amount, date: date, note: note)
        context.insert(transfer)
        commit()
        return transfer
    }

    func deleteTransfer(_ transfer: WalletTransfer) {
        context.delete(transfer)
        commit()
    }

    /// Số dư hiện tại của từng ví. Khoản ứng chưa trả là tiền đã ra khỏi ví; đã trả thì coi như tiền đã về.
    func walletBalances() -> [UUID: Int] {
        var movements: [WalletMovement] = []
        for expense in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.walletID != nil }))) ?? [] {
            if let id = expense.walletID { movements.append(WalletMovement(walletID: id, delta: -expense.amount, date: expense.date)) }
        }
        for loan in (try? context.fetch(FetchDescriptor<Loan>(predicate: #Predicate { $0.walletID != nil }))) ?? [] where !loan.isRepaid {
            if let id = loan.walletID { movements.append(WalletMovement(walletID: id, delta: -loan.amount, date: loan.date)) }
        }
        for transfer in (try? context.fetch(FetchDescriptor<WalletTransfer>())) ?? [] {
            movements += transfer.record.movements
        }
        return WalletBalances.balances(wallets: wallets().map(\.snapshot), movements: movements)
    }

    /// Ví dùng gần nhất, lưu trong App Group để intent cũng đọc được.
    static var lastWalletID: UUID? {
        get { AppGroup.defaults.string(forKey: SettingsKey.lastWallet).flatMap(UUID.init(uuidString:)) }
        set { AppGroup.defaults.set(newValue?.uuidString, forKey: SettingsKey.lastWallet) }
    }

    /// Ví chọn sẵn cho một lần ghi: ví dùng gần nhất nếu còn, không thì ví đầu tiên; nil khi chưa có ví nào.
    func defaultWalletID() -> UUID? {
        let all = wallets()
        if let last = Self.lastWalletID, all.contains(where: { $0.id == last }) { return last }
        return all.first?.id
    }

    // MARK: - Tin nhắn ngân hàng

    enum BankLogResult: Equatable {
        /// Tiền ra: đã ghi thành khoản chi.
        case expense(SavedBatch)
        /// Tiền vào: đã cộng vào ví.
        case income(amount: Int, walletName: String)
        /// Tiền vào nhưng không ví nào khớp, nên không có chỗ để ghi.
        case incomeIgnored(amount: Int)
        case duplicate
        case unreadable
    }

    /// Ghi một tin nhắn ngân hàng: tiền ra thành khoản chi (ví khớp từ khóa, không thì không gắn ví), tiền vào thành tiền nạp vào ví khớp.
    /// Cùng một tin nhắn chỉ ghi một lần. Nơi gọi phải kiểm tra Pro và `SaveGate.canSave` trước.
    func recordBankMessage(_ message: String, budget: BudgetSetting, now: Date, calendar: Calendar, defaults: UserDefaults = AppGroup.defaults) -> BankLogResult {
        guard let transaction = BankMessageParser.parse(message, now: now, calendar: calendar) else { return .unreadable }
        var seen = defaults.stringArray(forKey: SettingsKey.bankMessages) ?? []
        let fingerprint = BankMessageLog.fingerprint(message)
        guard !seen.contains(fingerprint) else { return .duplicate }
        defer {
            seen.append(fingerprint)
            defaults.set(Array(seen.suffix(BankMessageLog.capacity)), forKey: SettingsKey.bankMessages)
        }

        let all = wallets()
        let hint = [message, transaction.accountSuffix ?? ""].joined(separator: " ")
        let matched = WalletBalances.wallet(matching: hint, keywords: all.map { ($0.id, $0.keywords) })
        let date = transaction.date ?? now
        switch transaction.direction {
        case .credit:
            guard let id = matched, let wallet = all.first(where: { $0.id == id }) else { return .incomeIgnored(amount: transaction.amount) }
            addTransfer(from: nil, to: id, amount: transaction.amount, date: date, note: transaction.description ?? "")
            return .income(amount: transaction.amount, walletName: wallet.name)
        case .debit:
            let name = transaction.description ?? String(localized: "chi qua ngân hàng")
            let allowance = status(budget: budget, now: now, calendar: calendar).allowanceToday
            let draft = ExpenseDraft(
                name: name, amount: transaction.amount,
                categoryKey: CategoryClassifier.categoryKey(for: name, rules: rules()),
                isOutsideBudget: ExpenseParser.isOutsideBudget(amount: transaction.amount, dailyAllowance: allowance),
                date: date
            )
            return .expense(record([.expense(draft)], in: RecordContext(rawText: message, date: date, walletID: matched)))
        }
    }
}

/// Nhớ các tin nhắn ngân hàng đã ghi để phím tắt chạy hai lần không ghi trùng.
enum BankMessageLog {
    static let capacity = 300

    /// Dấu vân tay của một tin nhắn: chỉ xét chữ và số (bỏ dấu, hoa thường, khoảng trắng), băm FNV-1a 64 bit.
    static func fingerprint(_ message: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for scalar in TextNormalizer.fold(message).unicodeScalars where scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
            for byte in String(scalar).utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        return String(hash, radix: 16)
    }
}
