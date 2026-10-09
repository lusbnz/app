import SwiftUI

/// Lần đầu mở app: một câu hỏi duy nhất.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.calendar) private var calendar
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var budget: Int? { BudgetInput.parse(text) }

    var body: some View {
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
            Text("Không tính tiền nhà và các khoản cố định. Đổi lúc nào cũng được, không cần tài khoản.")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
            Spacer()
            Spacer()
            Button("Bắt đầu", action: start)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(budget == nil)
        }
        .padding(24)
        .xuScreen()
        .onAppear { isFocused = true }
    }

    private func start() {
        guard let budget else { return }
        withAnimation { settings.monthlyBudget = budget }
    }
}

#Preview {
    OnboardingView().xuPreview(budget: 0)
}
