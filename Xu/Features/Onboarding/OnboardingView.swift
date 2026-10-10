import SwiftUI

/// Lần đầu mở app: cách gõ, nhắc và gợi ý, rồi một câu hỏi cuối là ngân sách tháng.
/// Có ngân sách nghĩa là đã xong onboarding, nên bước ngân sách luôn là bước cuối.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case typing, reminders, budget
    }

    @Environment(AppSettings.self) private var settings
    @Environment(LocationProvider.self) private var location
    @Environment(\.calendar) private var calendar
    @State private var step = Step.typing
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var budget: Int? { BudgetInput.parse(text) }

    var body: some View {
        TabView(selection: $step) {
            page(typingStep).tag(Step.typing)
            page(remindersStep).tag(Step.reminders)
            page(budgetStep).tag(Step.budget)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .xuScreen()
        .animation(.snappy, value: step)
        .onChange(of: step) { _, newStep in isFocused = newStep == .budget }
    }

    /// Mỗi bước là một trang; vuốt ngang để chuyển bước.
    private func page(_ content: some View) -> some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(24)
    }

    // MARK: - Bước 1: cách gõ

    private static let examples: [(typed: LocalizedStringKey, meaning: LocalizedStringKey)] = [
        ("phở 45k, grab 32", "nhiều khoản trong một dòng"),
        ("nhậu 460k chia 4", "chỉ ghi phần của bạn: 115k"),
        ("hôm qua cơm 55k", "ghi cho ngày đã qua"),
        ("1 củ 2 tai nghe", "1,2 triệu, cứ gõ như nói"),
        ("ứng cho Minh 200k", "cho mượn, không tính vào ngân sách"),
    ]

    private var typingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Gõ một dòng là xong")
                .font(.title.weight(.bold))
            Text("Không cần chọn danh mục hay nhập từng ô. Nhẩm tự tách tên, số tiền và ngày.")
                .font(.body)
                .foregroundStyle(Color.xuTextSecondary)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Self.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.typed).font(.headline)
                        Text(example.meaning)
                            .font(.subheadline)
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 8)
            Text("Cũng nói được bằng micro, và chụp hóa đơn để chọn món của bạn.")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            Spacer()
            navigation()
        }
    }

    // MARK: - Bước 2: nhắc và gợi ý

    private var remindersStep: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Nhẩm nhắc khi bạn quên")
                .font(.title.weight(.bold))
            Text("Cả hai đều tùy chọn, mặc định tắt. Bật hay tắt lúc nào cũng được trong Tùy chỉnh.")
                .font(.body)
                .foregroundStyle(Color.xuTextSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Nhắc ghi lúc 21:00", isOn: $settings.remindsAtNine)
                    .frame(minHeight: 44)
                Text("Chỉ nhắc nếu hôm đó bạn chưa ghi gì.")
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
            }
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Gợi ý theo giờ và vị trí", isOn: $settings.suggestionsEnabled)
                    .frame(minHeight: 44)
                Text("Quán quen hiện sẵn một chạm là ghi. Vị trí chỉ xử lý trên máy, không gửi đi đâu.")
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
            }
            Spacer()
            navigation()
        }
        .onChange(of: settings.remindsAtNine) { _, isOn in
            // Chỉ xin quyền khi người dùng bật công tắc.
            Task {
                if isOn { _ = await NotificationManager.shared.requestAuthorization() }
                NotificationManager.shared.refreshDailyReminder()
            }
        }
        .onChange(of: settings.suggestionsEnabled) { _, isOn in
            if isOn {
                location.requestWhenInUse()
                location.refresh()
            }
        }
    }

    // MARK: - Bước 3: ngân sách

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Mỗi tháng bạn muốn tiêu bao nhiêu?")
                .font(.title.weight(.bold))
            TextField("9tr", text: $text)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(start)
                .accessibilityLabel("Ngân sách mỗi tháng")
            if let budget {
                let daily = BudgetCalculator.dailyAverage(monthlyBudget: budget, now: Date(), calendar: calendar)
                Text("Tức khoảng \(MoneyFormatter.short(daily)) mỗi ngày.")
                    .font(.title3)
                    .accessibilityLabel("Tức khoảng \(MoneyFormatter.spoken(daily)) mỗi ngày.")
            }
            Text("Tiền nhà và các khoản cố định thì thêm ở Tùy chỉnh, mục Khoản định kỳ: Nhẩm nhắc đến hạn và bạn chạm để ghi. Đổi ngân sách lúc nào cũng được, không cần tài khoản.")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            Spacer()
            Spacer()
            Button("Bắt đầu", action: start)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(budget == nil)
            Button("Quay lại") { step = .reminders }
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Chung

    /// Dấu chấm tiến độ và lời nhắc vuốt; có thể nhảy thẳng tới bước ngân sách.
    private func navigation() -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item == step ? Color.xuTextPrimary : Color.xuDivider)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            .padding(.bottom, 8)
            Label("Vuốt để tiếp tục", systemImage: "hand.draw")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityAction(named: "Tiếp") { advance() }
            Button("Bỏ qua") { step = .budget }
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func start() {
        guard let budget else { return }
        withAnimation { settings.monthlyBudget = budget }
    }
}

#Preview {
    OnboardingView().xuPreview(budget: 0)
}
