#if DEBUG
import Foundation
import SwiftData

/// Tham số khởi chạy chỉ có ở bản Debug, để xem nhanh các màn hình trên máy ảo:
/// `-reset` xóa sạch, `-demo` nạp dữ liệu mẫu, `-sample` thêm 90 ngày dữ liệu mẫu, `-week` tính ngân sách theo tuần, `-scrub N` nhảy tới ngày thứ N của dải ngày, `-pro` mở Pro, `-theme mint|peach|sky|coffee|graphite` (cần `-pro`), `-open entry|month|week|map|goals|goal|recurring|backup|csv|restore|settings|paywall|receipt|search`, `-recurring N` (cùng `-open recurring`: sửa khoản định kỳ thứ N), `-text "phở 45k"`, `-entryask "câu hỏi"`.
/// `-open receipt` đưa sẵn một hóa đơn mẫu vào bộ đọc. `-pro` mở Pennyline Pro, `-ask "câu hỏi"` hỏi Pennyline, `-budget 3tr` đặt ngân sách.
@MainActor
enum DebugLaunch {
    static func apply(settings: AppSettings, appState: AppState, container: ModelContainer) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let context = container.mainContext
        if arguments.contains("-reset") {
            try? context.delete(model: Expense.self)
            try? context.delete(model: Loan.self)
            try? context.delete(model: CategoryRule.self)
            try? context.delete(model: RecurringExpense.self)
            try? context.delete(model: CategoryBudget.self)
            settings.monthlyBudget = 0
            settings.suggestionsEnabled = false
            settings.remindsAtNine = false
            settings.leaveReminderEnabled = false
            settings.lastQuestion = ""
            settings.lastAnswer = ""
            AppGroup.defaults.removeObject(forKey: "saveQuota")
            for key in [
                SettingsKey.budgetPeriod, SettingsKey.weeklyBudget, SettingsKey.weeklySummary, SettingsKey.monthlySummary,
                SettingsKey.appTheme, SettingsKey.limitsShapeDaily, SettingsKey.placeLookup,
            ] {
                AppGroup.defaults.removeObject(forKey: key)
            }
            settings.budgetPeriod = .month
            ThemeStore.shared.theme = .lavender
        }
        if arguments.contains("-demo") {
            settings.monthlyBudget = 9_000_000
            settings.suggestionsEnabled = true
            let existing = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0
            if existing == 0 { seed(context) }
        }
        if arguments.contains("-sample") {
            ExpenseRecorder(context: context).insertSampleData(days: 90, now: Date(), calendar: .current)
        }
        if let budget = value(after: "-budget").flatMap(BudgetInput.parse) {
            settings.monthlyBudget = budget
        }
        if let index = value(after: "-scrub").flatMap(Int.init) {
            appState.debugScrubIndex = index
        }
        appState.debugRecurringIndex = value(after: "-recurring").flatMap(Int.init)
        if arguments.contains("-week") {
            settings.setBudgetPeriod(.week)
        }
        if arguments.contains("-pro") {
            EntitlementStore.shared.grantForDebug()
        }
        if let theme = value(after: "-theme").flatMap(AppTheme.init(rawValue:)) {
            ThemeStore.shared.theme = theme
        }
        try? context.save()
        let screen = value(after: "-open")
        let text = value(after: "-text") ?? ""
        let question = value(after: "-ask")
        appState.debugEntryQuestion = value(after: "-entryask")
        // Chờ giao diện gốc dựng xong rồi mới điều hướng, như khi người dùng chạm.
        Task {
            try? await Task.sleep(for: .seconds(1))
            switch screen {
            case "entry": appState.openEntry(text: text)
            case "month": appState.showsMonth = true
            case "week": appState.debugOpensWeek = true
            case "map", "goals", "goal":
                appState.debugMonthDestination = screen
                appState.showsMonth = true
            case "settings": appState.showsSettings = true
            case "recurring":
                seedRecurring(context)
                appState.debugSettingsDestination = "recurring"
                appState.showsSettings = true
            case "backup":
                appState.debugSettingsDestination = "backup"
                appState.showsSettings = true
            case "csv":
                appState.debugCSVText = sampleCSV
                appState.debugSettingsDestination = "backup"
                appState.showsSettings = true
            case "restore":
                appState.debugRestoreURL = prepareRestore(context, settings: settings)
                appState.debugSettingsDestination = "backup"
                appState.showsSettings = true
            case "search": appState.showsSearch = true
            case "paywall": appState.showsPaywall = true
            case "receipt":
                appState.receiptImage = SampleReceipt.image()
                appState.showsReceipt = true
            case nil where appState.debugEntryQuestion != nil: appState.openEntry(text: text)
            default: break
            }
            if let question { appState.ask(question) }
        }
    }

    /// Sao kê mẫu: một dòng trùng khoản có sẵn của `-demo` (phở 45k lúc 7:15 hôm nay), một khoản thu nhập, một dòng lỗi ngày.
    private static var sampleCSV: String {
        let calendar = Calendar.current
        func day(_ ago: Int) -> String {
            let date = calendar.date(byAdding: .day, value: -ago, to: Date()) ?? Date()
            let parts = calendar.dateComponents([.day, .month, .year], from: date)
            return String(format: "%02d/%02d/%d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 2026)
        }
        return """
        Sao kê tài khoản
        Ngày giao dịch;Nội dung giao dịch;Ghi nợ;Ghi có;Số dư
        \(day(0));Phở;45.000;;5.000.000
        \(day(2));THANH TOAN GRAB;32.000;;4.968.000
        \(day(3));LUONG THANG 10;;15.000.000;19.968.000
        \(day(3));Cơm tấm Sài Gòn;55.000;;19.913.000
        \(day(5));Tiền điện;850.000;;19.063.000
        31/02/2026;Ngày sai;10.000;;19.053.000
        """
    }

    /// Cho `-open restore`: sao lưu dữ liệu mẫu ra một tệp rồi xóa hết khoản chi, để thử khôi phục thật.
    private static func prepareRestore(_ context: ModelContext, settings: AppSettings) -> URL? {
        let recorder = ExpenseRecorder(context: context)
        if ((try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0) == 0 { seed(context) }
        try? context.save()
        let file = recorder.backupFile(settings: settings.backupSettings(), includesPhotos: false, now: Date())
        guard let data = try? BackupCodec.encode(file) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("debug-restore.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        try? context.delete(model: Expense.self)
        try? context.save()
        return url
    }

    /// Mỗi tần suất một khoản mẫu, để xem danh sách và màn sửa; chỉ thêm khi chưa có khoản nào.
    private static func seedRecurring(_ context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<RecurringExpense>())) ?? 0) == 0 else { return }
        let recorder = ExpenseRecorder(context: context)
        let now = Date()
        // Mỗi khoản lệch một giây để thứ tự theo ngày tạo luôn cố định.
        func at(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset)) }
        recorder.addRecurring(name: "Tiền nhà", amount: 3_000_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: true, now: at(0))
        recorder.addRecurring(
            name: "Gửi xe", amount: 20_000, categoryKey: "transport", dayOfMonth: 1, isOutsideBudget: false, now: at(1),
            frequency: .weekly, weekday: 2
        )
        recorder.addRecurring(
            name: "Dọn nhà", amount: 400_000, categoryKey: "bills", dayOfMonth: 1, isOutsideBudget: false, now: at(2),
            frequency: .biweekly, weekday: 7, remindDayBefore: true
        )
        recorder.addRecurring(
            name: "Bảo hiểm", amount: 1_500_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: true, now: at(3),
            frequency: .quarterly, monthOfYear: 2, autoRecord: true
        )
        recorder.addRecurring(
            name: "Tên miền", amount: 300_000, categoryKey: "bills", dayOfMonth: 15, isOutsideBudget: false, now: at(4),
            frequency: .yearly, monthOfYear: 3
        )
    }

    private static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let noon = calendar.date(bySettingHour: 12, minute: 15, second: 0, of: now) ?? now
        func add(_ name: String, _ amount: Int, _ category: String, daysAgo: Int, hour: Int = 12) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon),
                  let date = calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day),
                  date <= now || daysAgo > 0 else { return }
            let expense = Expense(name: name, amount: amount, categoryKey: category, date: min(date, now))
            expense.latitude = 10.7769
            expense.longitude = 106.7009
            context.insert(expense)
        }
        add("phở", 45_000, "food", daysAgo: 0, hour: 7)
        add("grab", 32_000, "transport", daysAgo: 0, hour: 8)
        for day in 1...min(7, max(1, calendar.component(.day, from: now) - 1)) {
            add("phở", 45_000, "food", daysAgo: day, hour: 7)
            add("cf", 29_000, "food", daysAgo: day, hour: 9)
            add("cơm tấm", 55_000, "food", daysAgo: day, hour: 12)
            add(day.isMultiple(of: 2) ? "đổ xăng" : "grab", day.isMultiple(of: 2) ? 80_000 : 32_000, "transport", daysAgo: day, hour: 18)
            add("bún chả", 60_000, "food", daysAgo: day, hour: 19)
        }
        context.insert(Loan(person: "Minh", amount: 200_000))
    }
}
#endif
