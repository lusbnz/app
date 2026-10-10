import SwiftData
import SwiftUI

/// Chữ gợi ý dưới mỗi mục tiêu tiết kiệm.
enum SavingsText {
    /// "Cần để dành 1,9tr mỗi tháng · còn 4 tháng", "Còn thiếu 7,5tr", "Đã đủ mục tiêu", "Đã quá hạn, còn thiếu 2tr".
    static func hint(_ progress: SavingsProgress) -> String {
        if progress.isDone { return String(localized: "Đã đủ mục tiêu") }
        let remaining = MoneyFormatter.short(progress.remaining)
        if progress.isOverdue { return String(localized: "Đã quá hạn, còn thiếu \(remaining)") }
        if let needed = progress.neededPerMonth, let months = progress.monthsLeft {
            return String(localized: "Cần để dành \(MoneyFormatter.short(needed)) mỗi tháng") + " · " + String(localized: "còn \(months) tháng")
        }
        return String(localized: "Còn thiếu \(remaining)")
    }
}

/// Tóm tắt một mục tiêu: tên, đã để dành trên mục tiêu, vệt highlight và gợi ý.
struct SavingsGoalRow: View {
    @Environment(\.calendar) private var calendar
    let goal: SavingsGoal
    let saved: Int
    let now: Date

    var body: some View {
        let progress = SavingsPlanner.progress(
            target: goal.targetAmount, saved: saved, deadline: goal.deadline, now: now, calendar: calendar
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name).font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text("\(MoneyFormatter.short(progress.saved)) / \(MoneyFormatter.short(progress.target))")
                    .monospacedDigit()
                    .foregroundStyle(Color.xuTextSecondary)
            }
            HighlightBar(fraction: progress.fraction, isWarning: progress.isOverdue)
            Text(SavingsText.hint(progress))
                .font(.footnote)
                .foregroundStyle(progress.isOverdue ? Color.red : Color.xuTextSecondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(goal.name), để dành \(MoneyFormatter.spoken(progress.saved)) trên \(MoneyFormatter.spoken(progress.target)). \(SavingsText.hint(progress))"))
    }
}

struct SavingsGoalForm: Identifiable {
    let id = UUID()
    var editing: SavingsGoal?
}

/// Danh sách mục tiêu tiết kiệm: thêm mục tiêu, chạm để xem và gửi tiền.
struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var deposits: [SavingsDeposit]
    @State private var form: SavingsGoalForm?

    var body: some View {
        let saved = Dictionary(grouping: deposits, by: \.goalID).mapValues { max(0, $0.reduce(0) { $0 + $1.amount }) }
        List {
            Section {
                ForEach(goals) { goal in
                    NavigationLink {
                        SavingsGoalDetailView(goal: goal)
                    } label: {
                        SavingsGoalRow(goal: goal, saved: saved[goal.id] ?? 0, now: Date())
                    }
                }
                Button("Thêm mục tiêu") { form = SavingsGoalForm(editing: nil) }
            } footer: {
                Text("Tiền để dành không phải chi tiêu nên không trừ vào ngân sách. Bạn tự gửi vào hoặc rút ra ở từng mục tiêu.")
            }
            .listRowBackground(Color.xuSurface)
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Mục tiêu tiết kiệm")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $form) { form in
            SavingsGoalEditor(form: form)
        }
    }
}

/// Thêm hoặc sửa một mục tiêu: tên, số tiền cần có, hạn (không bắt buộc).
struct SavingsGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    let form: SavingsGoalForm
    @State private var name = ""
    @State private var targetText = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()

    private var target: Int? { AmountParser.amount(from: targetText).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { SavingsPlanner.cleanName(name) != nil && target != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên mục tiêu") {
                    TextField("Du lịch Đà Lạt", text: $name)
                }
                .listRowBackground(Color.xuSurface)
                Section("Số tiền cần có") {
                    TextField("10tr", text: $targetText)
                        .monospacedDigit()
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    Toggle("Đặt hạn", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Hạn", selection: $deadline, in: calendar.startOfDay(for: Date())..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Đặt hạn thì Pennyline tính mỗi tháng cần để dành bao nhiêu.")
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle(form.editing == nil ? "Mục tiêu mới" : "Sửa mục tiêu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save).disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
        .fontDesign(.rounded)
    }

    private func load() {
        if let goal = form.editing {
            name = goal.name
            targetText = MoneyFormatter.full(goal.targetAmount)
            hasDeadline = goal.deadline != nil
            deadline = goal.deadline ?? (calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date())
        } else {
            deadline = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        }
    }

    private func save() {
        guard let target else { return }
        let recorder = ExpenseRecorder(context: modelContext)
        let due = hasDeadline ? deadline : nil
        if let goal = form.editing {
            recorder.updateGoal(goal, name: name, target: target, deadline: due)
        } else {
            recorder.addGoal(name: name, target: target, deadline: due)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { SavingsGoalsView() }
        .xuPreview()
}
