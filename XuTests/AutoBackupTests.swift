import Foundation
import SwiftData
import Testing
@testable import Xu

/// Sao lưu tự động ra một thư mục tạm thật.
@MainActor
struct AutoBackupTests {
    private let calendar = TestClock.calendar

    private func makeStore() -> (ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (container.mainContext, container)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("auto-backup-\(UUID().uuidString)", isDirectory: true)
    }

    private func addExpense(_ context: ModelContext, photo: Data? = nil) throws {
        let expense = Expense(name: "phở", amount: 45_000, categoryKey: "food", date: TestClock.date(2026, 10, 9, 7))
        expense.photo = photo
        context.insert(expense)
        try context.save()
    }

    @Test func writesTodaysBackupOnceAndItReadsBack() async throws {
        let (context, container) = makeStore()
        defer { withExtendedLifetime(container) {} }
        try addExpense(context)
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = await AutoBackup.runIfNeeded(
            context: context, settings: BackupSettings(monthlyBudget: 9_000_000), now: TestClock.now, calendar: calendar, directory: directory
        )
        #expect(url?.lastPathComponent == "pennyline-tu-dong-2026-10-09.json")
        let file = try BackupCodec.decode(Data(contentsOf: try #require(url)))
        #expect(file.expenses.map(\.name) == ["phở"])
        #expect(file.settings.monthlyBudget == 9_000_000)

        let again = await AutoBackup.runIfNeeded(
            context: context, settings: BackupSettings(), now: TestClock.date(2026, 10, 9, 22), calendar: calendar, directory: directory
        )
        #expect(again == nil)                                              // một ngày một bản
        #expect(AutoBackup.files(calendar: calendar, in: directory).map(\.name) == ["pennyline-tu-dong-2026-10-09.json"])
    }

    @Test func anEmptyStoreWritesNothing() async {
        let (context, container) = makeStore()
        defer { withExtendedLifetime(container) {} }
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = await AutoBackup.runIfNeeded(context: context, settings: BackupSettings(), now: TestClock.now, calendar: calendar, directory: directory)
        #expect(url == nil)
        #expect(AutoBackup.files(calendar: calendar, in: directory).isEmpty)
    }

    @Test func keepsOnlyTheNewestBackupsAndLeavesOtherFilesAlone() async throws {
        let (context, container) = makeStore()
        defer { withExtendedLifetime(container) {} }
        try addExpense(context)
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let foreign = directory.appendingPathComponent("ghi-chu-cua-toi.json")
        try Data("{}".utf8).write(to: foreign)

        for day in 1...(AutoBackup.keep + 2) {
            await AutoBackup.runIfNeeded(
                context: context, settings: BackupSettings(), now: TestClock.date(2026, 9, day), calendar: calendar, directory: directory
            )
        }
        let names = AutoBackup.files(calendar: calendar, in: directory).map(\.name)
        #expect(names.count == AutoBackup.keep)
        #expect(names.first == "pennyline-tu-dong-2026-09-16.json")
        #expect(names.last == "pennyline-tu-dong-2026-09-03.json")
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test func automaticBackupsLeaveOutPhotos() async throws {
        let (context, container) = makeStore()
        defer { withExtendedLifetime(container) {} }
        try addExpense(context, photo: Data([1, 2, 3]))
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(await AutoBackup.runIfNeeded(
            context: context, settings: BackupSettings(), now: TestClock.now, calendar: calendar, directory: directory
        ))
        #expect(try BackupCodec.decode(Data(contentsOf: url)).expenses.allSatisfy { $0.photo == nil })
    }

    @Test func fileListShowsSizeAndDeleteRemovesIt() async throws {
        let (context, container) = makeStore()
        defer { withExtendedLifetime(container) {} }
        try addExpense(context)
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        await AutoBackup.runIfNeeded(context: context, settings: BackupSettings(), now: TestClock.now, calendar: calendar, directory: directory)
        let file = try #require(AutoBackup.files(calendar: calendar, in: directory).first)
        #expect(file.bytes > 0)
        #expect(file.date == calendar.startOfDay(for: TestClock.now))
        AutoBackup.delete(file)
        #expect(AutoBackup.files(calendar: calendar, in: directory).isEmpty)
    }
}
