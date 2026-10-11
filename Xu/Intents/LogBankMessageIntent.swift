import AppIntents
import Foundation

/// Đọc một tin nhắn ngân hàng rồi ghi, không mở app. Dùng với tự động hóa "Khi tôi nhận được tin nhắn" của app Phím tắt:
/// chuyển nội dung tin nhắn vào tham số này. Tiền ra thành khoản chi, tiền vào cộng vào ví khớp từ khóa. Pennyline Pro.
struct LogBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi từ tin nhắn ngân hàng"
    static let description = IntentDescription("Đọc tin báo biến động số dư rồi ghi: tiền ra thành khoản chi, tiền vào cộng vào ví. Cùng một tin nhắn chỉ ghi một lần.")
    static let openAppWhenRun = false

    @Parameter(title: "Tin nhắn", requestValueDialog: "Tin nhắn ngân hàng nói gì?")
    var message: String

    init() {}

    init(message: String) {
        self.message = message
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let calendar = Calendar.current
        guard SaveGate.isPro else {
            return .result(dialog: "Ghi từ tin nhắn ngân hàng là tính năng của Pennyline Pro. Mở Pennyline để xem.")
        }
        let recorder = ExpenseRecorder(context: XuStore.shared.mainContext)
        switch recorder.recordBankMessage(message, budget: BudgetSetting.load(), now: now, calendar: calendar) {
        case .expense(let batch):
            return .result(dialog: "\(batch.summary).")
        case .income(let amount, let walletName):
            return .result(dialog: "Đã cộng \(MoneyFormatter.short(amount)) vào ví \(walletName).")
        case .incomeIgnored(let amount):
            return .result(dialog: "Tiền vào \(MoneyFormatter.short(amount)), không phải khoản chi nên Pennyline không ghi. Đặt từ khóa cho một ví để cộng vào ví đó.")
        case .duplicate:
            return .result(dialog: "Tin nhắn này đã ghi rồi.")
        case .unreadable:
            return .result(dialog: "Pennyline chưa đọc được tin nhắn này.")
        }
    }
}
