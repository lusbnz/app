import Foundation
import SwiftData
import Testing
@testable import Xu

/// Sao lưu rồi khôi phục qua SwiftData thật (trong bộ nhớ), và nhập CSV.
@MainActor
struct BackupRestoreTests {
    private let calendar = TestClock.calendar

    private func makeRecorder() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    /// Một mẫu của mỗi loại dữ liệu, với đủ các trường tùy chọn.
    private func seed(_ context: ModelContext) -> UUID {
        let expense = Expense(name: "phở bò", amount: 45_000, categoryKey: "custom-abc", date: TestClock.date(2026, 10, 9, 7))
        expense.createdAt = TestClock.date(2026, 10, 9, 8)
        expense.rawText = "phở bò 45k chia 4"
        expense.originalAmount = 180_000
        expense.splitCount = 4
        expense.foreignCurrency = "usd"
        expense.foreignMinor = 2000
        expense.latitude = 10.7769
        expense.longitude = 106.7009
        expense.placeName = "Phở Hòa"
        expense.photo = Data([0, 1, 2, 253, 254, 255])
        expense.isOutsideBudget = true
        context.insert(expense)
        context.insert(Expense(name: "cf", amount: 29_000, categoryKey: "food", date: TestClock.date(2026, 10, 8)))

        let loan = Loan(person: "Minh", amount: 200_000, date: TestClock.date(2026, 10, 7))
        loan.isRepaid = true
        context.insert(loan)
        context.insert(CategoryRule(keyword: "highlands", categoryKey: "food", updatedAt: TestClock.date(2026, 10, 1)))
        let category = CustomCategory(name: "Leo núi", createdAt: TestClock.date(2026, 9, 1), iconName: "figure.hiking")
        category.key = "custom-abc"
        context.insert(category)
        let limit = CategoryBudget(categoryKey: "food", amount: 3_000_000)
        limit.updatedAt = TestClock.date(2026, 10, 1)
        context.insert(limit)
        let plan = RecurringExpense(
            name: "bảo hiểm", amount: 1_500_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: true,
            createdAt: TestClock.date(2026, 1, 1), frequency: .quarterly, monthOfYear: 2, autoRecord: true, remindDayBefore: true
        )
        plan.handledMonth = "2026-08"
        context.insert(plan)
        let goal = SavingsGoal(name: "Đà Lạt", targetAmount: 10_000_000, deadline: TestClock.date(2027, 1, 1), createdAt: TestClock.date(2026, 9, 1))
        context.insert(goal)
        context.insert(SavingsDeposit(goalID: goal.id, amount: 500_000, date: TestClock.date(2026, 10, 2), note: "tháng 10"))
        try? context.save()
        return expense.id
    }

    @Test func backupThenRestoreIntoAnEmptyStoreReproducesEverything() throws {
        let (source, sourceContext, sourceContainer) = makeRecorder()
        defer { withExtendedLifetime(sourceContainer) {} }
        _ = seed(sourceContext)
        let settings = BackupSettings(monthlyBudget: 9_000_000, weeklyBudget: 0, budgetPeriod: "month", exchangeRates: ["usd": "25400"])
        let written = try BackupCodec.decode(BackupCodec.encode(source.backupFile(settings: settings, includesPhotos: true, now: TestClock.now)))
        #expect(written.itemCount == 9)

        let (target, _, targetContainer) = makeRecorder()
        defer { withExtendedLifetime(targetContainer) {} }
        let plan = BackupMerger.plan(written, existing: target.backupExisting(), settings: BackupSettings())
        #expect(plan.newItemCount == 9 && plan.alreadyPresent == 0)
        #expect(target.restore(plan) == 9)

        let again = target.backupFile(settings: settings, includesPhotos: true, now: TestClock.now)
        #expect(again == written)
    }

    @Test func restoringTwiceAddsNothingTheSecondTime() throws {
        let (source, sourceContext, sourceContainer) = makeRecorder()
        defer { withExtendedLifetime(sourceContainer) {} }
        _ = seed(sourceContext)
        let file = try BackupCodec.decode(BackupCodec.encode(source.backupFile(settings: BackupSettings(), includesPhotos: true, now: TestClock.now)))

        let (target, targetContext, targetContainer) = makeRecorder()
        defer { withExtendedLifetime(targetContainer) {} }
        target.restore(BackupMerger.plan(file, existing: target.backupExisting(), settings: BackupSettings()))
        let second = BackupMerger.plan(file, existing: target.backupExisting(), settings: BackupSettings())
        #expect(second.newItemCount == 0)
        #expect(second.alreadyPresent == 9)
        #expect(try targetContext.fetchCount(FetchDescriptor<Expense>()) == 2)
    }

    @Test func photosCanBeLeftOut() {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        _ = seed(context)
        #expect(recorder.backupFile(settings: BackupSettings(), includesPhotos: true, now: TestClock.now).expenses.contains { $0.photo != nil })
        #expect(recorder.backupFile(settings: BackupSettings(), includesPhotos: false, now: TestClock.now).expenses.allSatisfy { $0.photo == nil })
    }

    @Test func restoreKeepsWhatIsAlreadyOnTheDeviceAndAddsTheRest() throws {
        let (source, sourceContext, sourceContainer) = makeRecorder()
        defer { withExtendedLifetime(sourceContainer) {} }
        let sharedID = seed(sourceContext)
        let file = source.backupFile(settings: BackupSettings(), includesPhotos: true, now: TestClock.now)

        let (target, targetContext, targetContainer) = makeRecorder()
        defer { withExtendedLifetime(targetContainer) {} }
        let edited = Expense(name: "phở bò (đã sửa)", amount: 50_000, categoryKey: "food", date: TestClock.date(2026, 10, 9, 7))
        edited.id = sharedID
        targetContext.insert(edited)
        try targetContext.save()

        target.restore(BackupMerger.plan(file, existing: target.backupExisting(), settings: BackupSettings()))
        let expenses = try targetContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 2)
        #expect(expenses.first { $0.id == sharedID }?.amount == 50_000)       // bản trên máy giữ nguyên
        #expect(expenses.first { $0.id == sharedID }?.name == "phở bò (đã sửa)")
    }

    @Test func restoredRecurringPlanKeepsItsScheduleAndProgress() throws {
        let (source, sourceContext, sourceContainer) = makeRecorder()
        defer { withExtendedLifetime(sourceContainer) {} }
        _ = seed(sourceContext)
        let file = source.backupFile(settings: BackupSettings(), includesPhotos: false, now: TestClock.now)
        let (target, targetContext, targetContainer) = makeRecorder()
        defer { withExtendedLifetime(targetContainer) {} }
        target.restore(BackupMerger.plan(file, existing: target.backupExisting(), settings: BackupSettings()))
        let plan = try #require(targetContext.fetch(FetchDescriptor<RecurringExpense>()).first)
        #expect(plan.frequency == .quarterly && plan.monthOfYear == 2 && plan.dayOfMonth == 5)
        #expect(plan.autoRecord && plan.remindDayBefore && plan.isOutsideBudget)
        #expect(plan.handledMonth == "2026-08")
    }

    @Test func restoredCustomCategoryKeepsItsKeySoExpensesStillPointAtIt() throws {
        let (source, sourceContext, sourceContainer) = makeRecorder()
        defer { withExtendedLifetime(sourceContainer) {} }
        _ = seed(sourceContext)
        let file = source.backupFile(settings: BackupSettings(), includesPhotos: false, now: TestClock.now)
        let (target, targetContext, targetContainer) = makeRecorder()
        defer { withExtendedLifetime(targetContainer) {} }
        target.restore(BackupMerger.plan(file, existing: target.backupExisting(), settings: BackupSettings()))
        let category = try #require(targetContext.fetch(FetchDescriptor<CustomCategory>()).first)
        #expect(category.key == "custom-abc" && category.name == "Leo núi" && category.iconName == "figure.hiking")
        let catalog = CategoryCatalog(custom: [category])
        #expect(catalog.info(for: "custom-abc").title == "Leo núi")
    }

    @Test func aRuleFromAHandEditedFileIsNormalizedAndAnEmptyOneSkipped() throws {
        let (target, targetContext, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let file = BackupFile(createdAt: TestClock.now, rules: [
            BackupRule(keyword: "Phở  Bò", categoryKey: "food", updatedAt: TestClock.now),
            BackupRule(keyword: "   ", categoryKey: "food", updatedAt: TestClock.now),
        ])
        target.restore(BackupMerger.plan(file, existing: target.backupExisting(), settings: BackupSettings()))
        #expect(try targetContext.fetch(FetchDescriptor<CategoryRule>()).map(\.keyword) == ["pho bo"])
    }

    // MARK: - Nhập CSV

    @Test func importingWritesOneBatchAndUndoRemovesOnlyThatBatch() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        SaveGate.quota = SaveQuota(day: "x", count: 3)
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        context.insert(Expense(name: "có sẵn", amount: 1_000, categoryKey: "food", date: TestClock.date(2026, 10, 1)))
        try context.save()

        let rows = [
            ImportedExpense(date: TestClock.date(2026, 9, 5, 7), name: "phở", amount: 45_000, categoryKey: "food", isOutsideBudget: false, placeName: nil),
            ImportedExpense(date: TestClock.date(2026, 9, 6, 9), name: "tai nghe", amount: 1_200_000, categoryKey: "shopping", isOutsideBudget: true, placeName: "Tiki"),
        ]
        let batchID = recorder.importExpenses(rows, now: TestClock.now)
        let all = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
        #expect(all.count == 3)
        let imported = all.filter { $0.batchID == batchID }
        #expect(imported.map(\.name) == ["phở", "tai nghe"])
        #expect(imported.allSatisfy { $0.createdAt == TestClock.now })
        #expect(imported.last?.placeName == "Tiki" && imported.last?.isOutsideBudget == true)
        #expect(SaveGate.quota == SaveQuota(day: "x", count: 3))                // nhập không tốn lượt ghi

        #expect(recorder.undoImport(batchID: batchID) == 2)
        #expect(try context.fetch(FetchDescriptor<Expense>()).map(\.name) == ["có sẵn"])
        #expect(SaveGate.quota == SaveQuota(day: "x", count: 3))                // gỡ cũng không trả lượt
    }

    @Test func existingExpensesFeedTheImporterSoReimportingSkipsThem() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        context.insert(Expense(name: "Phở", amount: 45_000, categoryKey: "food", date: TestClock.date(2026, 10, 5, 7)))
        try context.save()
        let text = "Ngày,Giờ,Tên,Số tiền\n05/10/2026,07:00,phở,45000\n05/10/2026,09:00,cf,29000"
        let options = CSVImporter.Options(existing: recorder.existingSignatures(), now: TestClock.now, calendar: calendar)
        let result = try CSVImporter.importExpenses(from: text, options: options).get()
        #expect(result.duplicates == 1)
        #expect(result.rows.map(\.name) == ["cf"])
    }
}

@MainActor
struct BackupSettingsTests {
    private func makeSettings() -> (AppSettings, UserDefaults, [String]) {
        let names = ["backup-test-\(UUID().uuidString)", "backup-test-\(UUID().uuidString)"]
        let defaults = UserDefaults(suiteName: names[0]) ?? .standard
        let standard = UserDefaults(suiteName: names[1]) ?? .standard
        return (AppSettings(defaults: defaults, standardDefaults: standard), defaults, names)
    }

    @Test func settingsRoundTripThroughTheBackupSection() {
        let (settings, defaults, names) = makeSettings()
        defer { names.forEach { UserDefaults().removePersistentDomain(forName: $0) } }
        settings.monthlyBudget = 9_000_000
        settings.weeklyBudget = 2_100_000
        settings.budgetPeriod = .week
        ExchangeRates(overrides: [.usd: 25_400]).save(to: defaults)

        let backup = settings.backupSettings(ratesIn: defaults)
        #expect(backup == BackupSettings(monthlyBudget: 9_000_000, weeklyBudget: 2_100_000, budgetPeriod: "week", exchangeRates: ["usd": "25400"]))

        let (fresh, freshDefaults, freshNames) = makeSettings()
        defer { freshNames.forEach { UserDefaults().removePersistentDomain(forName: $0) } }
        fresh.apply(backup, ratesIn: freshDefaults)
        #expect(fresh.monthlyBudget == 9_000_000 && fresh.weeklyBudget == 2_100_000 && fresh.budgetPeriod == .week)
        #expect(ExchangeRates.load(from: freshDefaults).rate(for: .usd) == 25_400)
    }
}
