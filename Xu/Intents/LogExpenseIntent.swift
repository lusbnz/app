import AppIntents
import Foundation

/// Chạy bộ tách trên một dòng chữ rồi lưu, không mở app.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi chi tiêu"
    static let description = IntentDescription("Ghi một hoặc nhiều khoản chi bằng một dòng chữ, ví dụ “phở 45k, grab 32”.")
    static let openAppWhenRun = false

    @Parameter(title: "Khoản chi", requestValueDialog: "Bạn vừa tiêu gì?")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let calendar = Calendar.current
        guard SaveGate.canSave(now: now, calendar: calendar) else {
            return .result(dialog: "Bản miễn phí cho gõ 5 lần mỗi ngày. Mở Nhẩm để dùng Nhẩm Pro.")
        }
        let recorder = ExpenseRecorder(context: XuStore.shared.mainContext)
        let budget = AppGroup.defaults.integer(forKey: SettingsKey.monthlyBudget)
        guard let batch = recorder.record(text: text, monthlyBudget: budget, now: now, calendar: calendar) else {
            return .result(dialog: "Nhẩm chưa đọc được số tiền trong “\(text)”.")
        }
        let remaining = recorder.status(monthlyBudget: budget, now: now, calendar: calendar).remainingToday
        let warning = batch.warning.map { " \($0)." } ?? ""
        return .result(dialog: "\(batch.summary). Hôm nay còn \(MoneyFormatter.short(remaining)).\(warning)")
    }
}
