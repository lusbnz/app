import Foundation

/// Những gì máy đã có, để khôi phục không tạo bản lặp.
struct BackupExisting: Equatable, Sendable {
    var expenseIDs: Set<UUID> = []
    var loanIDs: Set<UUID> = []
    var ruleKeywords: Set<String> = []
    var customCategoryKeys: Set<String> = []
    var limitKeys: Set<String> = []
    var recurringIDs: Set<UUID> = []
    var goalIDs: Set<UUID> = []
    var depositIDs: Set<UUID> = []
}

/// Phần của bản sao lưu sẽ được thêm vào máy.
struct BackupPlan: Equatable, Sendable {
    var expenses: [BackupExpense] = []
    var loans: [BackupLoan] = []
    var rules: [BackupRule] = []
    var customCategories: [BackupCategory] = []
    var limits: [BackupLimit] = []
    var recurring: [BackupRecurring] = []
    var goals: [BackupGoal] = []
    var deposits: [BackupDeposit] = []
    /// Số mục trong tệp mà máy đã có; giữ bản trên máy, không ghi đè.
    var alreadyPresent = 0
    /// Cài đặt sau khi hợp nhất; nil khi không có gì đổi.
    var settings: BackupSettings?

    var newItemCount: Int {
        expenses.count + loans.count + rules.count + customCategories.count + limits.count
            + recurring.count + goals.count + deposits.count
    }

    var isEmpty: Bool { newItemCount == 0 && settings == nil }
}

/// Khôi phục theo kiểu hợp nhất: chỉ thêm cái máy chưa có (theo mã, hoặc theo từ khóa và danh mục với luật và hạn mức),
/// không xóa và không ghi đè gì trên máy. Nhờ vậy khôi phục lên máy mới thì có lại tất cả, còn khôi phục lên máy đang dùng
/// thì chỉ lấy lại phần đã mất.
enum BackupMerger {
    static func plan(_ file: BackupFile, existing: BackupExisting, settings current: BackupSettings) -> BackupPlan {
        var plan = BackupPlan()
        var skipped = 0
        plan.expenses = fresh(file.expenses, known: existing.expenseIDs, id: \.id, skipped: &skipped)
        plan.loans = fresh(file.loans, known: existing.loanIDs, id: \.id, skipped: &skipped)
        plan.rules = fresh(file.rules, known: existing.ruleKeywords, id: \.keyword, skipped: &skipped)
        plan.customCategories = fresh(file.customCategories, known: existing.customCategoryKeys, id: \.key, skipped: &skipped)
        plan.limits = fresh(file.categoryLimits, known: existing.limitKeys, id: \.categoryKey, skipped: &skipped)
        plan.recurring = fresh(file.recurring, known: existing.recurringIDs, id: \.id, skipped: &skipped)
        plan.goals = fresh(file.goals, known: existing.goalIDs, id: \.id, skipped: &skipped)
        // Khoản gửi tiết kiệm mất mục tiêu thì không có chỗ để hiện, nên bỏ.
        let goalIDs = existing.goalIDs.union(plan.goals.map(\.id))
        let attached = file.deposits.filter { goalIDs.contains($0.goalID) }
        skipped += file.deposits.count - attached.count
        plan.deposits = fresh(attached, known: existing.depositIDs, id: \.id, skipped: &skipped)
        plan.alreadyPresent = skipped

        let merged = merge(file.settings, into: current)
        plan.settings = merged == current ? nil : merged
        return plan
    }

    /// Chỉ điền chỗ còn trống: ngân sách chưa đặt thì lấy từ tệp, tỷ giá chưa chỉnh thì lấy từ tệp.
    static func merge(_ backup: BackupSettings, into current: BackupSettings) -> BackupSettings {
        var result = current
        if current.monthlyBudget <= 0 { result.monthlyBudget = max(0, backup.monthlyBudget) }
        if current.weeklyBudget <= 0 { result.weeklyBudget = max(0, backup.weeklyBudget) }
        if current.monthlyBudget <= 0, current.weeklyBudget <= 0 { result.budgetPeriod = backup.budgetPeriod }
        for (code, rate) in backup.exchangeRates where result.exchangeRates[code] == nil {
            result.exchangeRates[code] = rate
        }
        return result
    }

    /// Các mục chưa có trên máy, bỏ luôn mục bị lặp ngay trong tệp.
    private static func fresh<Item, ID: Hashable>(
        _ items: [Item], known: Set<ID>, id: (Item) -> ID, skipped: inout Int
    ) -> [Item] {
        var seen = known
        var result: [Item] = []
        for item in items {
            if seen.insert(id(item)).inserted {
                result.append(item)
            } else {
                skipped += 1
            }
        }
        return result
    }
}

/// Tên tệp sao lưu và quy tắc giữ lại bản tự động.
enum BackupNaming {
    enum Kind: String, Sendable {
        case manual = "sao-luu"
        case automatic = "tu-dong"
    }

    /// "pennyline-sao-luu-2026-10-10.json", "pennyline-tu-dong-2026-10-10.json".
    static func fileName(_ kind: Kind, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return "pennyline-\(kind.rawValue)-\(parts.year ?? 0)-\(String(format: "%02d", parts.month ?? 0))-\(String(format: "%02d", parts.day ?? 0)).json"
    }

    /// Ngày ghi trong tên của một bản tự động; nil khi tên không đúng dạng (tệp lạ không bao giờ bị xóa).
    static func automaticDate(fromFileName name: String, calendar: Calendar) -> Date? {
        let prefix = "pennyline-\(Kind.automatic.rawValue)-", suffix = ".json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { return nil }
        let day = name.dropFirst(prefix.count).dropLast(suffix.count).split(separator: "-").map(String.init)
        guard day.count == 3, day[0].count == 4, day[1].count == 2, day[2].count == 2,
              let year = Int(day[0]), let month = Int(day[1]), let date = Int(day[2]),
              let result = calendar.date(from: DateComponents(year: year, month: month, day: date)) else { return nil }
        // Calendar tự dồn tháng 13 hay ngày 31/2 sang kỳ sau; ngày như vậy là sai.
        let back = calendar.dateComponents([.year, .month, .day], from: result)
        guard back.year == year, back.month == month, back.day == date else { return nil }
        return result
    }

    /// Hôm nay chưa có bản tự động nào thì cần sao lưu.
    static func needsAutomaticBackup(existing names: [String], now: Date, calendar: Calendar) -> Bool {
        !names.contains { name in
            automaticDate(fromFileName: name, calendar: calendar).map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
    }

    /// Các bản tự động cần xóa để chỉ còn `keep` bản mới nhất.
    static func automaticNamesToDelete(from names: [String], keep: Int, calendar: Calendar) -> [String] {
        let dated = names.compactMap { name in automaticDate(fromFileName: name, calendar: calendar).map { (name, $0) } }
        let newestFirst = dated.sorted { ($0.1, $0.0) > ($1.1, $1.0) }
        return newestFirst.dropFirst(max(0, keep)).map(\.0)
    }
}
