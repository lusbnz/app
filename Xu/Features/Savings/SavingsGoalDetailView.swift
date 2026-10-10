import SwiftData
import SwiftUI

/// Một mục tiêu: đã để dành bao nhiêu, cần bao nhiêu mỗi tháng, gửi thêm hoặc rút bớt, và lịch sử.
struct SavingsGoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    /// Không lọc trong `@Query`: màn hình nằm trong `navigationDestination` sẽ truy vấn lại liên tục (xem `MonthView`).
    @Query(sort: \SavingsDeposit.date, order: .reverse) private var allDeposits: [SavingsDeposit]
    let goal: SavingsGoal
    @State private var sheet: DepositMode?
    @State private var editing: SavingsGoalForm?
    @State private var confirmsDelete = false
    @State private var cannotDelete = false

    private var deposits: [SavingsDeposit] { allDeposits.filter { $0.goalID == goal.id } }
    private var recorder: ExpenseRecorder { ExpenseRecorder(context: modelContext) }

    var body: some View {
        let deposits = deposits
        let saved = max(0, deposits.reduce(0) { $0 + $1.amount })
        let progress = SavingsPlanner.progress(
            target: goal.targetAmount, saved: saved, deadline: goal.deadline, now: Date(), calendar: calendar
        )
        List {
            Section {
                summary(progress)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            Section {
                HStack(spacing: 10) {
                    Button { sheet = .deposit } label: { Label("Gửi thêm", systemImage: "plus") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { sheet = .withdraw } label: { Label("Rút bớt", systemImage: "minus") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(saved == 0)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if !deposits.isEmpty {
                Section("Lịch sử") {
                    ForEach(deposits) { deposit in
                        historyRow(deposit)
                    }
                }
                .listRowBackground(Color.xuSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Sửa mục tiêu", systemImage: "pencil") { editing = SavingsGoalForm(editing: goal) }
                    Button("Xóa mục tiêu", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $sheet) { mode in
            SavingsDepositSheet(goal: goal, mode: mode, saved: saved)
        }
        .sheet(item: $editing) { form in
            SavingsGoalEditor(form: form)
        }
        .confirmationDialog("Xóa mục tiêu này?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Xóa “\(goal.name)”", role: .destructive) {
                recorder.deleteGoal(goal)
                dismiss()
            }
        } message: {
            Text("Các lần gửi và rút của mục tiêu cũng bị xóa. Việc này không hoàn lại được.")
        }
        .alert("Chưa xóa được", isPresented: $cannotDelete) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Lần gửi này đã được rút một phần. Hãy xóa lần rút trước.")
        }
    }

    private func summary(_ progress: SavingsProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HighlightedNumber(text: MoneyFormatter.short(progress.saved), fraction: progress.fraction, size: 56)
            Text("đã để dành, trên \(MoneyFormatter.short(progress.target))")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            HighlightBar(fraction: progress.fraction, isWarning: progress.isOverdue)
            Text(SavingsText.hint(progress))
                .font(.body)
                .foregroundStyle(progress.isOverdue ? Color.red : Color.xuTextPrimary)
            if let deadline = goal.deadline {
                Text("Hạn: \(deadline.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func historyRow(_ deposit: SavingsDeposit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deposit.amount > 0 ? "Gửi vào" : "Rút ra")
                Text(deposit.note.isEmpty
                     ? deposit.date.formatted(date: .abbreviated, time: .omitted)
                     : "\(deposit.date.formatted(date: .abbreviated, time: .omitted)) · \(deposit.note)")
                    .font(.caption)
                    .foregroundStyle(Color.xuTextSecondary)
            }
            Spacer()
            Text((deposit.amount > 0 ? "+" : "−") + MoneyFormatter.short(abs(deposit.amount)))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button("Xóa", systemImage: "trash", role: .destructive) {
                if !recorder.deleteDeposit(deposit) { cannotDelete = true }
            }
        }
    }
}

enum DepositMode: String, Identifiable {
    case deposit, withdraw

    var id: String { rawValue }
}

/// Nhập số tiền gửi vào hoặc rút ra của một mục tiêu.
struct SavingsDepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let goal: SavingsGoal
    let mode: DepositMode
    /// Số đang để dành, để không cho rút quá.
    let saved: Int
    @State private var amountText = ""
    @State private var note = ""
    @FocusState private var focused: Bool

    private var amount: Int? { AmountParser.amount(from: amountText).flatMap { $0 > 0 ? $0 : nil } }
    private var tooMuch: Bool { mode == .withdraw && (amount ?? 0) > saved }
    private var canSave: Bool { amount != nil && !tooMuch }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("500k", text: $amountText)
                        .monospacedDigit()
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                        .submitLabel(.done)
                } header: {
                    Text("Số tiền")
                } footer: {
                    if tooMuch {
                        Text("Chỉ rút được tối đa \(MoneyFormatter.short(saved)).").foregroundStyle(Color.red)
                    }
                }
                .listRowBackground(Color.xuSurface)
                Section("Ghi chú") {
                    TextField("không bắt buộc", text: $note)
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle(mode == .deposit ? "Gửi vào “\(goal.name)”" : "Rút từ “\(goal.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save).disabled(!canSave) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .fontDesign(.rounded)
    }

    private func save() {
        guard let amount else { return }
        ExpenseRecorder(context: modelContext).addDeposit(
            to: goal, amount: mode == .deposit ? amount : -amount, note: note
        )
        dismiss()
    }
}
