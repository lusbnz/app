import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Việc người dùng muốn làm với một tệp: khôi phục bản sao lưu (chọn tệp, hoặc một tệp đã biết như bản tự động) hay nhập CSV.
enum BackupFileRequest: Identifiable, Equatable {
    case chooseBackup
    case restore(URL)
    case chooseCSV

    var id: String {
        switch self {
        case .chooseBackup: "chooseBackup"
        case .restore(let url): "restore-\(url.path)"
        case .chooseCSV: "chooseCSV"
        }
    }
}

/// Nội dung tệp CSV đã đọc, chờ màn xem trước.
struct CSVImportSource: Identifiable {
    let id = UUID()
    let name: String
    let text: String
}

/// Gắn một lần ở màn gốc của luồng: chọn tệp, xem trước, xác nhận, rồi khôi phục hoặc nhập vào máy.
/// Khôi phục theo kiểu hợp nhất, chỉ thêm cái máy chưa có, không xóa và không ghi đè (`BackupMerger`).
/// Cả hai việc dùng chung một bộ chọn tệp vì nhiều `fileImporter` trên một màn hình chỉ có cái cuối chạy.
struct BackupFileHost: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Binding var request: BackupFileRequest?
    @State private var picking: Purpose?
    @State private var pending: PendingRestore?
    @State private var notice: Notice?
    @State private var csv: CSVImportSource?

    private enum Purpose {
        case backup, csv

        var types: [UTType] {
            switch self {
            case .backup: [.json]
            case .csv: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
            }
        }
    }

    private struct PendingRestore: Identifiable {
        let id = UUID()
        var file: BackupFile
        var plan: BackupPlan
    }

    private struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, new in
                guard let new else { return }
                request = nil
                switch new {
                case .chooseBackup: picking = .backup
                case .chooseCSV: picking = .csv
                case .restore(let url): loadBackup(url)
                }
            }
            .fileImporter(
                isPresented: Binding { picking != nil } set: { if !$0 { picking = nil } },
                allowedContentTypes: picking?.types ?? [.json]
            ) { result in
                let purpose = picking
                picking = nil
                guard case .success(let url) = result else { return }
                if purpose == .csv { loadCSV(url) } else { loadBackup(url) }
            }
            .confirmationDialog(
                "Khôi phục bản sao lưu?", isPresented: Binding { pending != nil } set: { if !$0 { pending = nil } },
                titleVisibility: .visible, presenting: pending
            ) { pending in
                Button("Khôi phục") { restore(pending) }
                Button("Hủy", role: .cancel) {}
            } message: { pending in
                Text(summary(of: pending))
            }
            .alert(
                notice?.title ?? "", isPresented: Binding { notice != nil } set: { if !$0 { notice = nil } }, presenting: notice
            ) { _ in
                Button("Đóng", role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
            .sheet(item: $csv) { source in
                CSVImportView(source: source)
            }
            #if DEBUG
            .task {
                // Cờ chạy thử `-open csv`: mở thẳng màn xem trước với một sao kê mẫu.
                guard let text = AppState.shared.debugCSVText else { return }
                AppState.shared.debugCSVText = nil
                try? await Task.sleep(for: .milliseconds(800))
                csv = CSVImportSource(name: "sao-ke-mau.csv", text: text)
            }
            #endif
    }

    // MARK: - Đọc tệp

    /// Đọc tệp người dùng chọn (cần xin quyền truy cập tệp ngoài app) hoặc tệp trong thư mục của app.
    private func data(at url: URL, limit: Int) -> Data? {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { return nil }
        return try? Data(contentsOf: url)
    }

    private func loadBackup(_ url: URL) {
        guard let data = data(at: url, limit: BackupCodec.maxBytes) else {
            show(String(localized: "Không đọc được tệp"), String(localized: "Tệp không mở được hoặc quá lớn."))
            return
        }
        do {
            let file = try BackupCodec.decode(data)
            let recorder = ExpenseRecorder(context: modelContext)
            let plan = BackupMerger.plan(file, existing: recorder.backupExisting(), settings: settings.backupSettings())
            if plan.isEmpty {
                show(String(localized: "Không có gì mới"), String(localized: "Máy đã có đủ mọi thứ trong bản sao lưu này."))
            } else {
                pending = PendingRestore(file: file, plan: plan)
            }
        } catch BackupError.newerVersion {
            show(String(localized: "Không khôi phục được"), String(localized: "Tệp này tạo bởi bản Pennyline mới hơn. Bạn cập nhật Pennyline rồi thử lại."))
        } catch BackupError.unreadable {
            show(String(localized: "Không khôi phục được"), String(localized: "Tệp sao lưu bị hỏng hoặc thiếu phần bắt buộc."))
        } catch {
            show(String(localized: "Không khôi phục được"), String(localized: "Đây không phải tệp sao lưu của Pennyline."))
        }
    }

    private func loadCSV(_ url: URL) {
        guard let data = data(at: url, limit: ImportText.maxBytes), let text = ImportText.decode(data) else {
            show(String(localized: "Không đọc được tệp"), String(localized: "Tệp trống, không mở được hoặc quá lớn."))
            return
        }
        csv = CSVImportSource(name: url.lastPathComponent, text: text)
    }

    // MARK: - Khôi phục

    private func summary(of pending: PendingRestore) -> String {
        let plan = pending.plan
        var lines = [String(localized: "Bản sao lưu ngày \(VietnameseDate.dayTitle(pending.file.createdAt, calendar: calendar)).")]
        let others = plan.newItemCount - plan.expenses.count
        if others == 0 {
            lines.append(String(localized: "Sẽ thêm \(plan.expenses.count) khoản chi."))
        } else if plan.expenses.isEmpty {
            lines.append(String(localized: "Sẽ thêm \(others) mục (khoản ứng, danh mục, luật, hạn mức, khoản định kỳ, mục tiêu tiết kiệm)."))
        } else {
            lines.append(String(localized: "Sẽ thêm \(plan.expenses.count) khoản chi và \(others) mục khác (khoản ứng, danh mục, luật, hạn mức, khoản định kỳ, mục tiêu tiết kiệm)."))
        }
        if plan.alreadyPresent > 0 {
            lines.append(String(localized: "\(plan.alreadyPresent) mục máy đã có, giữ nguyên."))
        }
        if plan.settings != nil {
            lines.append(String(localized: "Ngân sách và tỷ giá máy chưa đặt sẽ lấy từ bản này."))
        }
        lines.append(String(localized: "Không xóa hay ghi đè gì trên máy."))
        return lines.joined(separator: "\n")
    }

    private func restore(_ pending: PendingRestore) {
        let count = ExpenseRecorder(context: modelContext).restore(pending.plan)
        if let merged = pending.plan.settings { settings.apply(merged) }
        // Chờ hộp xác nhận đóng hẳn rồi mới hiện thông báo kết quả.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            show(String(localized: "Đã khôi phục"), String(localized: "Đã thêm \(count) mục vào máy."))
        }
    }

    private func show(_ title: String, _ message: String) {
        notice = Notice(title: title, message: message)
    }
}

extension View {
    /// Cho một màn hình khả năng khôi phục bản sao lưu và nhập CSV; đặt `request` để bắt đầu.
    func backupFileHost(request: Binding<BackupFileRequest?>) -> some View {
        modifier(BackupFileHost(request: request))
    }
}
