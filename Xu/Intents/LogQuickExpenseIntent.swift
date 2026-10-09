import AppIntents
import Foundation

/// Ghi một khoản biết sẵn tên và số tiền, không mở app. Dùng cho nút một chạm ở widget.
struct LogQuickExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi nhanh một khoản"
    static let description = IntentDescription("Ghi một khoản chi với tên và số tiền cho sẵn, không mở app.")
    static let openAppWhenRun = false

    @Parameter(title: "Tên khoản")
    var name: String

    @Parameter(title: "Số tiền (đồng)")
    var amount: Int

    init() {}

    init(name: String, amount: Int) {
        self.name = name
        self.amount = amount
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let calendar = Calendar.current
        guard amount > 0 else {
            return .result(dialog: "Số tiền phải lớn hơn 0.")
        }
        guard SaveGate.canSave(now: now, calendar: calendar) else {
            return .result(dialog: "Bản miễn phí cho gõ 5 lần mỗi ngày. Mở Xu để dùng Xu Pro.")
        }
        let recorder = ExpenseRecorder(context: XuStore.shared.mainContext)
        let budget = AppGroup.defaults.integer(forKey: SettingsKey.monthlyBudget)
        let batch = recorder.recordQuick(name: name, amount: amount, monthlyBudget: budget, now: now, calendar: calendar)
        let remaining = recorder.status(monthlyBudget: budget, now: now, calendar: calendar).remainingToday
        return .result(dialog: "\(batch.summary). Hôm nay còn \(MoneyFormatter.short(remaining)).")
    }
}
