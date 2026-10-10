import Foundation
import SwiftData
import Testing
@testable import Xu

struct BackupFileTests {
    private func sample() -> BackupFile {
        let goalID = UUID()
        return BackupFile(
            createdAt: TestClock.now,
            settings: BackupSettings(monthlyBudget: 9_000_000, weeklyBudget: 2_000_000, budgetPeriod: "week", exchangeRates: ["usd": "25400"]),
            expenses: [
                BackupExpense(
                    id: UUID(), name: "phở bò", amount: 45_000, categoryKey: "food", date: TestClock.date(2026, 10, 9, 7),
                    createdAt: TestClock.date(2026, 10, 9, 8), rawText: "phở bò 45k", batchID: UUID(), isOutsideBudget: false,
                    originalAmount: 180_000, splitCount: 4, foreignCurrency: "usd", foreignMinor: 2000,
                    latitude: 10.7769, longitude: 106.7009, placeName: "Phở Hòa", photo: Data([0, 1, 2, 253, 254, 255])
                ),
                BackupExpense(
                    id: UUID(), name: "", amount: 1_000, categoryKey: "custom-abc", date: TestClock.date(2026, 10, 8),
                    createdAt: TestClock.date(2026, 10, 8), rawText: "", batchID: UUID(), isOutsideBudget: true
                ),
            ],
            loans: [BackupLoan(id: UUID(), person: "Minh", amount: 200_000, date: TestClock.date(2026, 10, 7), isRepaid: true)],
            rules: [BackupRule(keyword: "highlands", categoryKey: "food", updatedAt: TestClock.date(2026, 10, 1))],
            customCategories: [BackupCategory(key: "custom-abc", name: "Leo núi", createdAt: TestClock.date(2026, 9, 1), iconName: "figure.hiking")],
            categoryLimits: [BackupLimit(categoryKey: "food", amount: 3_000_000, updatedAt: TestClock.date(2026, 10, 1))],
            recurring: [BackupRecurring(
                id: UUID(), name: "bảo hiểm", amount: 1_500_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: true,
                createdAt: TestClock.date(2026, 1, 1), handledMonth: "2026-08", frequency: "quarterly", weekday: 2, monthOfYear: 2,
                autoRecord: true, remindDayBefore: true
            )],
            goals: [BackupGoal(id: goalID, name: "Đà Lạt", targetAmount: 10_000_000, createdAt: TestClock.date(2026, 9, 1), deadline: TestClock.date(2027, 1, 1))],
            deposits: [BackupDeposit(id: UUID(), goalID: goalID, amount: 500_000, date: TestClock.date(2026, 10, 2), note: "tháng 10")]
        )
    }

    @Test func roundTripsEverySection() throws {
        let file = sample()
        #expect(try BackupCodec.decode(BackupCodec.encode(file)) == file)
        #expect(try BackupCodec.decode(BackupCodec.encode(file, pretty: false)) == file)
    }

    @Test func compactFilesAreSmallerThanPrettyOnes() throws {
        let file = sample()
        #expect(try BackupCodec.encode(file, pretty: false).count < BackupCodec.encode(file, pretty: true).count)
    }

    @Test func theFileIsPlainReadableJSON() throws {
        let text = try String(decoding: BackupCodec.encode(sample()), as: UTF8.self)
        #expect(text.contains("\"app\" : \"Pennyline\""))
        #expect(text.contains("phở bò") && text.contains("Leo núi"))
        #expect(!text.contains("\\/"))
    }

    @Test func rejectsFilesThatAreNotBackups() {
        #expect(throws: BackupError.notABackup) { try BackupCodec.decode(Data("hello".utf8)) }
        #expect(throws: BackupError.notABackup) { try BackupCodec.decode(Data(#"{"app":"Other","version":1}"#.utf8)) }
        #expect(throws: BackupError.notABackup) { try BackupCodec.decode(Data(#"{"version":1}"#.utf8)) }
        #expect(throws: BackupError.notABackup) { try BackupCodec.decode(Data("[1,2]".utf8)) }
    }

    @Test func rejectsFilesFromANewerVersion() {
        #expect(throws: BackupError.newerVersion(99)) {
            try BackupCodec.decode(Data(#"{"app":"Pennyline","version":99,"createdAt":"2026-10-10T00:00:00Z"}"#.utf8))
        }
    }

    @Test func rejectsBackupsMissingRequiredParts() {
        #expect(throws: BackupError.unreadable) { try BackupCodec.decode(Data(#"{"app":"Pennyline","version":1}"#.utf8)) }
        #expect(throws: BackupError.unreadable) {
            try BackupCodec.decode(Data(#"{"app":"Pennyline","version":1,"createdAt":"2026-10-10T00:00:00Z","expenses":[{"id":"x"}]}"#.utf8))
        }
    }

    @Test func missingSectionsAreEmpty() throws {
        let file = try BackupCodec.decode(Data(#"{"app":"Pennyline","version":1,"createdAt":"2026-10-10T00:00:00Z"}"#.utf8))
        #expect(file.itemCount == 0)
        #expect(file.settings == BackupSettings())
    }

    @Test func countsEverySection() {
        #expect(sample().itemCount == 2 + 1 + 1 + 1 + 1 + 1 + 1 + 1)
    }
}

struct BackupMergerTests {
    private func expense(_ id: UUID = UUID(), name: String = "phở") -> BackupExpense {
        BackupExpense(
            id: id, name: name, amount: 45_000, categoryKey: "food", date: TestClock.date(2026, 10, 9), createdAt: TestClock.date(2026, 10, 9),
            rawText: "", batchID: UUID(), isOutsideBudget: false
        )
    }

    @Test func addsOnlyWhatTheDeviceLacks() {
        let have = UUID(), lack = UUID()
        let file = BackupFile(createdAt: TestClock.now, expenses: [expense(have), expense(lack)])
        let plan = BackupMerger.plan(file, existing: BackupExisting(expenseIDs: [have]), settings: BackupSettings())
        #expect(plan.expenses.map(\.id) == [lack])
        #expect(plan.alreadyPresent == 1)
        #expect(plan.newItemCount == 1)
        #expect(plan.settings == nil)
    }

    @Test func aRepeatedItemInsideTheFileCountsOnce() {
        let id = UUID()
        let file = BackupFile(createdAt: TestClock.now, expenses: [expense(id), expense(id, name: "bản lặp")])
        let plan = BackupMerger.plan(file, existing: BackupExisting(), settings: BackupSettings())
        #expect(plan.expenses.map(\.name) == ["phở"])
        #expect(plan.alreadyPresent == 1)
    }

    @Test func rulesCategoriesAndLimitsAreMatchedByTheirKeys() {
        let file = BackupFile(
            createdAt: TestClock.now,
            rules: [BackupRule(keyword: "grab", categoryKey: "transport", updatedAt: TestClock.now), BackupRule(keyword: "cf", categoryKey: "food", updatedAt: TestClock.now)],
            customCategories: [BackupCategory(key: "custom-1", name: "A", createdAt: TestClock.now, iconName: "")],
            categoryLimits: [BackupLimit(categoryKey: "food", amount: 1, updatedAt: TestClock.now), BackupLimit(categoryKey: "fun", amount: 2, updatedAt: TestClock.now)]
        )
        let existing = BackupExisting(ruleKeywords: ["grab"], customCategoryKeys: ["custom-1"], limitKeys: ["food"])
        let plan = BackupMerger.plan(file, existing: existing, settings: BackupSettings())
        #expect(plan.rules.map(\.keyword) == ["cf"])
        #expect(plan.customCategories.isEmpty)
        #expect(plan.limits.map(\.categoryKey) == ["fun"])
        #expect(plan.alreadyPresent == 3)
    }

    @Test func depositsNeedAGoalOnTheDeviceOrInTheFile() {
        let kept = UUID(), restored = UUID(), orphan = UUID()
        let file = BackupFile(
            createdAt: TestClock.now,
            goals: [BackupGoal(id: restored, name: "g", targetAmount: 1, createdAt: TestClock.now, deadline: nil)],
            deposits: [
                BackupDeposit(id: UUID(), goalID: kept, amount: 1, date: TestClock.now, note: ""),
                BackupDeposit(id: UUID(), goalID: restored, amount: 2, date: TestClock.now, note: ""),
                BackupDeposit(id: UUID(), goalID: orphan, amount: 3, date: TestClock.now, note: ""),
            ]
        )
        let plan = BackupMerger.plan(file, existing: BackupExisting(goalIDs: [kept]), settings: BackupSettings())
        #expect(plan.deposits.map(\.amount) == [1, 2])
        #expect(plan.alreadyPresent == 1)
    }

    @Test func settingsOnlyFillEmptySlots() {
        let backup = BackupSettings(monthlyBudget: 9_000_000, weeklyBudget: 2_000_000, budgetPeriod: "week", exchangeRates: ["usd": "25400", "eur": "27000"])
        let fresh = BackupMerger.merge(backup, into: BackupSettings())
        #expect(fresh == backup)
        let used = BackupSettings(monthlyBudget: 5_000_000, weeklyBudget: 0, budgetPeriod: "month", exchangeRates: ["usd": "26000"])
        let merged = BackupMerger.merge(backup, into: used)
        #expect(merged.monthlyBudget == 5_000_000)            // đã đặt thì giữ
        #expect(merged.weeklyBudget == 2_000_000)             // chưa đặt thì lấy
        #expect(merged.budgetPeriod == "month")               // đã có ngân sách thì không đổi kiểu tính
        #expect(merged.exchangeRates == ["usd": "26000", "eur": "27000"])
    }

    @Test func aPlanWithNothingNewIsEmpty() {
        let id = UUID()
        let backup = BackupSettings(monthlyBudget: 9_000_000)
        let file = BackupFile(createdAt: TestClock.now, settings: backup, expenses: [expense(id)])
        let plan = BackupMerger.plan(file, existing: BackupExisting(expenseIDs: [id]), settings: backup)
        #expect(plan.isEmpty)
    }

    @Test func aBackupWithOnlyNewSettingsIsNotEmpty() {
        let file = BackupFile(createdAt: TestClock.now, settings: BackupSettings(monthlyBudget: 9_000_000))
        let plan = BackupMerger.plan(file, existing: BackupExisting(), settings: BackupSettings())
        #expect(plan.newItemCount == 0 && !plan.isEmpty)
        #expect(plan.settings?.monthlyBudget == 9_000_000)
    }
}

struct BackupNamingTests {
    private let calendar = TestClock.calendar

    @Test func namesFilesByKindAndDay() {
        #expect(BackupNaming.fileName(.manual, now: TestClock.now, calendar: calendar) == "pennyline-sao-luu-2026-10-09.json")
        #expect(BackupNaming.fileName(.automatic, now: TestClock.date(2026, 1, 5), calendar: calendar) == "pennyline-tu-dong-2026-01-05.json")
    }

    @Test func readsTheDayFromAnAutomaticName() {
        #expect(BackupNaming.automaticDate(fromFileName: "pennyline-tu-dong-2026-10-09.json", calendar: calendar) == calendar.startOfDay(for: TestClock.now))
    }

    @Test(arguments: [
        "pennyline-sao-luu-2026-10-09.json", "pennyline-tu-dong-2026-10-09.txt", "pennyline-tu-dong-.json",
        "pennyline-tu-dong-2026-13-09.json", "pennyline-tu-dong-2026-02-31.json", "pennyline-tu-dong-26-10-09.json", "ghi-chu.json",
    ])
    func ignoresNamesThatAreNotAutomaticBackups(name: String) {
        #expect(BackupNaming.automaticDate(fromFileName: name, calendar: calendar) == nil)
    }

    @Test func needsABackupUntilTodaysFileExists() {
        let yesterday = "pennyline-tu-dong-2026-10-08.json", today = "pennyline-tu-dong-2026-10-09.json"
        #expect(BackupNaming.needsAutomaticBackup(existing: [], now: TestClock.now, calendar: calendar))
        #expect(BackupNaming.needsAutomaticBackup(existing: [yesterday, "pennyline-sao-luu-2026-10-09.json"], now: TestClock.now, calendar: calendar))
        #expect(!BackupNaming.needsAutomaticBackup(existing: [yesterday, today], now: TestClock.now, calendar: calendar))
    }

    @Test func keepsTheNewestAutomaticBackupsAndNeverTouchesOtherFiles() {
        let names = [
            "pennyline-tu-dong-2026-10-01.json", "pennyline-tu-dong-2026-10-05.json", "pennyline-tu-dong-2026-10-03.json",
            "pennyline-tu-dong-2026-10-09.json", "pennyline-sao-luu-2026-09-01.json", "anh-cua-toi.json",
        ]
        let doomed = BackupNaming.automaticNamesToDelete(from: names, keep: 2, calendar: calendar)
        #expect(doomed == ["pennyline-tu-dong-2026-10-03.json", "pennyline-tu-dong-2026-10-01.json"])
        #expect(BackupNaming.automaticNamesToDelete(from: names, keep: 10, calendar: calendar).isEmpty)
        #expect(BackupNaming.automaticNamesToDelete(from: names, keep: 0, calendar: calendar).count == 4)
    }
}
