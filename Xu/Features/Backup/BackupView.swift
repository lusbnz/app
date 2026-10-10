import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Tệp sao lưu chỉ được tạo khi người dùng chọn nơi chia sẻ. Đọc dữ liệu trên luồng chính, mã hóa JSON ngoài luồng chính.
struct BackupExport: Transferable {
    let settings: BackupSettings

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let now = Date()
            let file = await MainActor.run {
                ExpenseRecorder(context: XuStore.shared.mainContext).backupFile(settings: export.settings, includesPhotos: true, now: now)
            }
            let data = try BackupCodec.encode(file)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(BackupNaming.fileName(.manual, now: now, calendar: .current))
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Sao lưu và khôi phục bằng tệp, sao lưu tự động hằng ngày (Pennyline Pro), và nhập khoản chi từ CSV.
struct BackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(EntitlementStore.self) private var store
    @State private var request: BackupFileRequest?
    @State private var showsPaywall = false
    @State private var autoFiles: [AutoBackupFile] = []
    @State private var expenseCount = 0

    var body: some View {
        List {
            manualSection
            automaticSection
            csvSection
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Sao lưu và nhập dữ liệu")
        .navigationBarTitleDisplayMode(.inline)
        .backupFileHost(request: $request)
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .onAppear(perform: reload)
        #if DEBUG
        .task {
            // Cờ chạy thử `-open restore`: khôi phục từ tệp vừa sao lưu.
            guard let url = AppState.shared.debugRestoreURL else { return }
            AppState.shared.debugRestoreURL = nil
            try? await Task.sleep(for: .milliseconds(800))
            request = .restore(url)
        }
        #endif
    }

    // MARK: - Sao lưu bằng tệp

    private var manualSection: some View {
        Section {
            ShareLink(
                item: BackupExport(settings: settings.backupSettings()),
                preview: SharePreview(BackupNaming.fileName(.manual, now: Date(), calendar: calendar))
            ) {
                HStack {
                    Text("Tạo bản sao lưu").foregroundStyle(Color.xuTextPrimary)
                    Spacer()
                    Text("\(expenseCount) khoản").foregroundStyle(Color.xuTextSecondary)
                }
            }
            Button("Khôi phục từ tệp…") { request = .chooseBackup }
        } header: {
            Text("Sao lưu")
        } footer: {
            Text("Một tệp .json đọc được, chứa khoản chi kèm ảnh, danh mục, luật, hạn mức, khoản định kỳ, mục tiêu tiết kiệm, ngân sách và tỷ giá. Cất vào iCloud Drive hoặc gửi cho chính bạn. Khôi phục chỉ thêm cái máy chưa có, không xóa hay ghi đè gì.")
        }
        .listRowBackground(Color.xuSurface)
    }

    // MARK: - Sao lưu tự động

    private var automaticSection: some View {
        Section {
            Toggle(isOn: Binding {
                store.isPro && settings.autoBackupEnabled
            } set: { isOn in
                guard store.isPro else {
                    showsPaywall = true
                    return
                }
                settings.autoBackupEnabled = isOn
                if isOn { runAutomatic() }
            }) {
                HStack {
                    Text("Sao lưu tự động mỗi ngày")
                    if !store.isPro { ButterLabel(text: "PRO") }
                }
            }
            ForEach(autoFiles) { file in
                HStack {
                    Button { request = .restore(file.url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(VietnameseDate.dayTitle(file.date, calendar: calendar)).foregroundStyle(Color.xuTextPrimary)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(Color.xuTextSecondary)
                        }
                    }
                    Spacer()
                    ShareLink(item: file.url) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chia sẻ bản sao lưu")
                }
                .swipeActions {
                    Button("Xóa", role: .destructive) {
                        AutoBackup.delete(file)
                        reload()
                    }
                }
            }
        } header: {
            Text("Sao lưu tự động")
        } footer: {
            Text(store.isPro
                 ? "Mỗi ngày mở Pennyline, một bản được lưu trên máy (giữ \(AutoBackup.keep) bản mới nhất, không kèm ảnh cho nhẹ). Chạm một bản để khôi phục, hoặc gửi nó đi để cất nơi khác."
                 : "Sao lưu tự động là của Pennyline Pro. Sao lưu và khôi phục bằng tệp ở trên luôn miễn phí.")
        }
        .listRowBackground(Color.xuSurface)
    }

    // MARK: - Nhập CSV

    private var csvSection: some View {
        Section {
            Button("Nhập từ tệp CSV…") { request = .chooseCSV }
        } header: {
            Text("Nhập từ CSV")
        } footer: {
            Text("Đọc được tệp Pennyline đã xuất và sao kê ngân hàng có cột ngày và số tiền. Khoản đã có trên máy (cùng giờ, tên và số tiền) được bỏ qua, và nhập xong vẫn hoàn tác được.")
        }
        .listRowBackground(Color.xuSurface)
    }

    private func reload() {
        autoFiles = AutoBackup.files(calendar: calendar)
        expenseCount = (try? modelContext.fetchCount(FetchDescriptor<Expense>())) ?? 0
    }

    private func runAutomatic() {
        Task {
            await AutoBackup.runIfNeeded(context: modelContext, settings: settings.backupSettings(), now: Date(), calendar: calendar)
            reload()
        }
    }
}

#Preview {
    NavigationStack { BackupView() }
        .xuPreview()
}
