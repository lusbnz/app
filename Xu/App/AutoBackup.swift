import Foundation
import SwiftData

struct AutoBackupFile: Identifiable, Equatable, Sendable {
    var name: String
    var url: URL
    var date: Date
    var bytes: Int

    var id: String { name }
}

/// Sao lưu tự động (Pennyline Pro): mỗi ngày mở app tạo một tệp trong thư mục riêng của app, giữ `keep` bản mới nhất.
/// Tệp nằm trong Application Support nên được sao lưu cùng máy (iCloud hoặc Finder); chưa chép sang iCloud Drive vì dự án chưa bật iCloud.
/// Bản tự động không kèm ảnh cho nhẹ; tạo bản bằng tay thì có ảnh.
@MainActor
enum AutoBackup {
    static let keep = 14

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Backups", isDirectory: true)
    }

    /// Các bản tự động đang có, mới nhất trước. Tệp lạ trong thư mục bị bỏ qua.
    static func files(calendar: Calendar, in directory: URL = AutoBackup.directory) -> [AutoBackupFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url -> AutoBackupFile? in
            guard let date = BackupNaming.automaticDate(fromFileName: url.lastPathComponent, calendar: calendar) else { return nil }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return AutoBackupFile(name: url.lastPathComponent, url: url, date: date, bytes: bytes)
        }
        .sorted { ($0.date, $0.name) > ($1.date, $1.name) }
    }

    /// Tạo bản của hôm nay nếu chưa có và máy có dữ liệu, rồi xóa bớt bản cũ. Trả về tệp vừa tạo, nil nếu không cần hoặc không ghi được.
    @discardableResult
    static func runIfNeeded(
        context: ModelContext, settings: BackupSettings, now: Date, calendar: Calendar, directory: URL = AutoBackup.directory
    ) async -> URL? {
        let existing = files(calendar: calendar, in: directory).map(\.name)
        guard BackupNaming.needsAutomaticBackup(existing: existing, now: now, calendar: calendar) else { return nil }
        let file = ExpenseRecorder(context: context).backupFile(settings: settings, includesPhotos: false, now: now)
        guard file.itemCount > 0 else { return nil }
        let url = directory.appendingPathComponent(BackupNaming.fileName(.automatic, now: now, calendar: calendar))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try await Task.detached(priority: .utility) { try BackupCodec.encode(file, pretty: false) }.value
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        for name in BackupNaming.automaticNamesToDelete(from: existing + [url.lastPathComponent], keep: keep, calendar: calendar) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        return url
    }

    static func delete(_ file: AutoBackupFile) {
        try? FileManager.default.removeItem(at: file.url)
    }
}
