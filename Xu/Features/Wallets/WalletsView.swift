import SwiftData
import SwiftUI

/// Ví (Pennyline Pro): số dư từng ví, thêm và sửa ví, chuyển tiền giữa các ví hoặc nạp tiền từ bên ngoài.
struct WalletsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(EntitlementStore.self) private var store
    @Query(sort: \Wallet.createdAt) private var wallets: [Wallet]
    @Query(sort: \WalletTransfer.date, order: .reverse) private var transfers: [WalletTransfer]
    /// Để số dư tính lại khi khoản chi hoặc khoản ứng đổi. Không lọc trong `@Query` (xem `MonthView`).
    @Query private var expenses: [Expense]
    @Query private var loans: [Loan]
    @State private var form: WalletForm?
    @State private var showsTransfer = false
    @State private var showsPaywall = false

    var body: some View {
        let balances = balances
        List {
            Section {
                ForEach(wallets) { wallet in
                    Button { form = WalletForm(editing: wallet) } label: {
                        HStack {
                            Label(wallet.name, systemImage: wallet.kind.symbol)
                                .foregroundStyle(Color.xuTextPrimary)
                            Spacer()
                            Text(MoneyFormatter.short(balances[wallet.id] ?? wallet.openingBalance))
                                .foregroundStyle((balances[wallet.id] ?? 0) < 0 ? Color.red : Color.xuTextSecondary)
                        }
                    }
                    .swipeActions {
                        Button("Xóa", role: .destructive) { ExpenseRecorder(context: modelContext).deleteWallet(wallet) }
                    }
                }
                Button {
                    if store.isPro { form = WalletForm(editing: nil) } else { showsPaywall = true }
                } label: {
                    HStack {
                        Text("Thêm ví")
                        if !store.isPro { ButterLabel(text: "PRO") }
                    }
                }
                if wallets.count >= 1 {
                    Button("Chuyển hoặc nạp tiền") { showsTransfer = true }
                }
            } header: {
                if wallets.count > 1 {
                    Text("Tổng \(MoneyFormatter.short(wallets.reduce(0) { $0 + (balances[$1.id] ?? 0) }))")
                }
            } footer: {
                Text("Ví chỉ để biết tiền đang nằm ở đâu, không ảnh hưởng ngân sách: ngân sách tính mọi khoản chi của mọi ví. Số dư là số ban đầu cộng mọi khoản chi, khoản ứng và lần chuyển tiền từ ngày tạo ví. Xóa ví không xóa khoản chi của nó.")
            }
            .listRowBackground(Color.xuSurface)

            if !transfers.isEmpty {
                Section("Chuyển tiền gần đây") {
                    ForEach(transfers.prefix(30)) { transfer in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(of: transfer))
                                Text(subtitle(of: transfer))
                                    .font(.caption)
                                    .foregroundStyle(Color.xuTextSecondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.short(transfer.amount)).foregroundStyle(Color.xuTextSecondary)
                        }
                        .swipeActions {
                            Button("Xóa", role: .destructive) { ExpenseRecorder(context: modelContext).deleteTransfer(transfer) }
                        }
                    }
                }
                .listRowBackground(Color.xuSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Ví")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $form) { WalletEditor(form: $0) }
        .sheet(isPresented: $showsTransfer) { TransferEditor(wallets: wallets) }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    /// Đọc `expenses`, `loans`, `transfers` để SwiftUI biết tính lại khi chúng đổi.
    private var balances: [UUID: Int] {
        _ = (expenses.count, loans.count, transfers.count)
        return ExpenseRecorder(context: modelContext).walletBalances()
    }

    private func name(_ id: UUID?) -> String {
        guard let id else { return String(localized: "bên ngoài") }
        return wallets.first { $0.id == id }?.name ?? String(localized: "ví đã xóa")
    }

    /// "VCB → Tiền mặt", "bên ngoài → VCB"
    private func title(of transfer: WalletTransfer) -> String {
        "\(name(transfer.fromID)) → \(name(transfer.toID))"
    }

    private func subtitle(of transfer: WalletTransfer) -> String {
        let day = VietnameseDate.relativeDay(transfer.date, now: Date(), calendar: calendar)
        return transfer.note.isEmpty ? day : "\(day) · \(transfer.note)"
    }
}

struct WalletForm: Identifiable {
    let id = UUID()
    var editing: Wallet?
}

/// Thêm hoặc sửa một ví.
struct WalletEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let form: WalletForm
    @State private var name = ""
    @State private var kind = WalletKind.cash
    @State private var balanceText = ""
    @State private var keywords = ""

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Để trống là 0; có chữ thì phải đọc được (cho phép số âm như "-200k" cho dư nợ thẻ).
    private var balance: Int? {
        balanceText.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : WalletBalances.signedAmount(from: balanceText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên ví", text: $name)
                    Picker("Loại", selection: $kind) {
                        ForEach(WalletKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Số dư ban đầu, ví dụ 5tr", text: $balanceText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Số dư ban đầu là số tiền ví đang có lúc này. Dư nợ thẻ thì gõ số âm, ví dụ -200k.")
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    TextField("vcb, vietcombank, 0011", text: $keywords)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Từ khóa tin nhắn ngân hàng")
                } footer: {
                    Text("Tin nhắn nào có một trong các từ này (tên ngân hàng, vài số cuối tài khoản) thì thuộc ví này. Ngăn cách bằng dấu phẩy. Bỏ trống nếu không dùng phím tắt đọc tin nhắn.")
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle(form.editing == nil ? "Ví mới" : "Sửa ví")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu", action: save).disabled(cleanName.isEmpty || balance == nil)
                }
            }
            .onAppear {
                guard let wallet = form.editing else { return }
                name = wallet.name
                kind = wallet.kind
                balanceText = wallet.openingBalance == 0 ? "" : (wallet.openingBalance < 0 ? "-" : "") + MoneyFormatter.grouped(abs(wallet.openingBalance))
                keywords = wallet.keywords
            }
        }
        .fontDesign(.rounded)
    }

    private func save() {
        guard let balance else { return }
        let recorder = ExpenseRecorder(context: modelContext)
        if let wallet = form.editing {
            recorder.updateWallet(wallet, name: cleanName, kind: kind, openingBalance: balance, keywords: keywords)
        } else {
            recorder.addWallet(name: cleanName, kind: kind, openingBalance: balance, keywords: keywords, now: Date())
        }
        dismiss()
    }
}

/// Chuyển tiền giữa hai ví, hoặc nạp tiền từ bên ngoài, hoặc rút ra ngoài.
struct TransferEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let wallets: [Wallet]
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()

    private var amount: Int? { AmountParser.amount(from: amountText).flatMap { $0 > 0 ? $0 : nil } }
    private var isValid: Bool {
        amount.map { WalletTransferRecord(from: from, to: to, amount: $0, date: date).isValid } ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    picker("Từ", selection: $from)
                    picker("Đến", selection: $to)
                    TextField("Số tiền, ví dụ 500k", text: $amountText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    DatePicker("Ngày", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Ghi chú (không bắt buộc)", text: $note)
                } footer: {
                    Text("Chọn “bên ngoài” ở ô Từ để ghi tiền vào ví (lương, nạp tiền), ở ô Đến để ghi tiền rút ra không phải chi tiêu. Chuyển tiền không tính vào ngân sách.")
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle("Chuyển tiền")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        guard let amount else { return }
                        ExpenseRecorder(context: modelContext).addTransfer(from: from, to: to, amount: amount, date: date, note: note.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                // Một ví thì mặc định là nạp tiền vào ví đó; từ hai ví thì chuyển từ ví đầu sang ví thứ hai.
                if wallets.count == 1 { to = wallets[0].id } else { from = wallets.first?.id; to = wallets.dropFirst().first?.id }
            }
        }
        .fontDesign(.rounded)
    }

    private func picker(_ title: LocalizedStringKey, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("bên ngoài").tag(UUID?.none)
            ForEach(wallets) { Text($0.name).tag(UUID?.some($0.id)) }
        }
    }
}

extension WalletKind {
    var title: LocalizedStringKey {
        switch self {
        case .cash: "Tiền mặt"
        case .bank: "Ngân hàng"
        case .card: "Thẻ"
        case .ewallet: "Ví điện tử"
        }
    }
}

#Preview {
    NavigationStack { WalletsView() }
        .xuPreview()
}
