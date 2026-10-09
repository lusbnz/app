import SwiftUI

/// Tùy chỉnh: ngân sách tháng, nhắc và gợi ý, hướng dẫn Siri, Xu Pro.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @State private var budgetText = ""
    @State private var showsPaywall = false
    @FocusState private var budgetFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Ngân sách tháng") {
                    TextField("9tr", text: $budgetText)
                        .monospacedDigit()
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($budgetFocused)
                        .onSubmit(commitBudget)
                        .accessibilityLabel("Ngân sách tháng")
                        .accessibilityValue(MoneyFormatter.spoken(settings.monthlyBudget))
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    Toggle("Nhắc ghi lúc 21:00 nếu hôm đó chưa ghi gì", isOn: $settings.remindsAtNine)
                    Toggle("Gợi ý theo vị trí và giờ", isOn: $settings.suggestionsEnabled)
                    Toggle("Nhắc khi rời quán quen", isOn: $settings.leaveReminderEnabled)
                } header: {
                    Text("Nhắc và gợi ý")
                } footer: {
                    Text("Vị trí và ảnh hóa đơn được xử lý trên máy, không gửi đi đâu.")
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    NavigationLink("Siri, Phím tắt và Nút Tác vụ") {
                        ShortcutsGuideView()
                    }
                    Button {
                        showsPaywall = true
                    } label: {
                        HStack {
                            Text("Xu Pro").foregroundStyle(Color.xuTextPrimary)
                            Spacer()
                            ButterLabel(text: "PRO")
                        }
                    }
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle("Tùy chỉnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        commitBudget()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .onAppear { budgetText = MoneyFormatter.full(settings.monthlyBudget) }
            .onChange(of: settings.suggestionsEnabled) { _, isOn in
                // Chỉ xin quyền vị trí khi người dùng bật công tắc.
                if isOn {
                    location.requestWhenInUse()
                    location.refresh()
                }
            }
            .onChange(of: settings.remindsAtNine) { _, isOn in
                // Chỉ xin quyền thông báo khi người dùng bật công tắc.
                Task {
                    if isOn { _ = await NotificationManager.shared.requestAuthorization() }
                    NotificationManager.shared.refreshDailyReminder()
                }
            }
            .onChange(of: budgetFocused) { _, focused in
                if !focused { commitBudget() }
            }
        }
        .fontDesign(.rounded)
    }

    private func commitBudget() {
        if let budget = BudgetInput.parse(budgetText) {
            settings.monthlyBudget = budget
        }
        budgetText = MoneyFormatter.full(settings.monthlyBudget)
    }
}

#Preview {
    SettingsView().xuPreview()
}
