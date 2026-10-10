import SwiftUI

/// Tùy chỉnh, chia nhóm: ngân sách, ghi chép, nhắc và gợi ý, hiển thị (giao diện, ngôn ngữ), dữ liệu, trợ giúp và Nhẩm Pro.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @Environment(AppLock.self) private var lock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @State private var sampleMessage: String?
    @State private var budgetText = ""
    @State private var showsPaywall = false
    @State private var explainsAlwaysLocation = false
    @State private var lockUnavailable = false
    @FocusState private var budgetFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    TextField("9tr", text: $budgetText)
                        .monospacedDigit()
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($budgetFocused)
                        .onSubmit(commitBudget)
                        .accessibilityLabel("Ngân sách tháng")
                        .accessibilityValue(MoneyFormatter.spoken(settings.monthlyBudget))
                    NavigationLink("Hạn mức danh mục") {
                        CategoryLimitsView()
                    }
                    Toggle("Hạn mức danh mục tính vào hạn mức ngày", isOn: $settings.limitsShapeDaily)
                } header: {
                    Text("Ngân sách")
                } footer: {
                    Text("Khi bật, tiền trong hạn mức của từng danh mục được giữ riêng: hạn mức ngày chỉ tính trên phần ngân sách còn lại, và khoản chi trong hạn mức danh mục không làm nó tụt. Chi vượt hạn mức danh mục thì trừ vào hạn mức ngày.")
                }
                .listRowBackground(Color.xuSurface)
                Section("Ghi chép") {
                    NavigationLink("Khoản định kỳ") {
                        RecurringView()
                    }
                    NavigationLink("Danh mục và luật") {
                        CategoriesView()
                    }
                    NavigationLink("Tỷ giá ngoại tệ") {
                        ExchangeRatesView()
                    }
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    Toggle("Nhắc ghi lúc 21:00 nếu hôm đó chưa ghi gì", isOn: $settings.remindsAtNine)
                    Toggle("Gợi ý theo vị trí và giờ", isOn: $settings.suggestionsEnabled)
                    Toggle("Nhắc khi rời quán quen", isOn: Binding {
                        settings.leaveReminderEnabled
                    } set: { isOn in
                        // Giải thích trước, rồi mới xin quyền vị trí "Luôn luôn".
                        if isOn { explainsAlwaysLocation = true } else { setLeaveReminder(false) }
                    })
                } header: {
                    Text("Nhắc và gợi ý")
                } footer: {
                    Text("Vị trí và ảnh hóa đơn được xử lý trên máy, không gửi đi đâu.")
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    Picker("Giao diện", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Ngôn ngữ", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Hiển thị")
                } footer: {
                    if settings.needsRelaunchForLanguage {
                        Text("Đóng hẳn rồi mở lại app để đổi ngôn ngữ.")
                    }
                }
                .listRowBackground(Color.xuSurface)
                Section {
                    Toggle("Khóa app bằng \(lock.method.title)", isOn: Binding {
                        lock.isEnabled
                    } set: { isOn in
                        Task {
                            let changed = await lock.setEnabled(isOn)
                            if !changed, isOn, !lock.canEnable { lockUnavailable = true }
                        }
                    })
                } header: {
                    Text("Bảo mật")
                } footer: {
                    Text("Nhẩm khóa khi mở app và khi ra ngoài app. Quên Face ID thì nhập mật mã máy. Ghi nhanh từ Siri và Phím tắt vẫn ghi được khi app khóa, nhưng không đọc được số liệu.")
                }
                .listRowBackground(Color.xuSurface)
                Section("Dữ liệu") {
                    ExportDataRow()
                }
                .listRowBackground(Color.xuSurface)
                #if DEBUG
                sampleDataSection
                #endif
                Section("Trợ giúp và Nhẩm Pro") {
                    NavigationLink("Siri, Phím tắt và Nút Tác vụ") {
                        ShortcutsGuideView()
                    }
                    Button {
                        showsPaywall = true
                    } label: {
                        HStack {
                            Text("Nhẩm Pro").foregroundStyle(Color.xuTextPrimary)
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
            .alert("Chưa khóa được app", isPresented: $lockUnavailable) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text("Máy chưa đặt mật mã hoặc Face ID. Bạn đặt trong Cài đặt của iPhone rồi bật lại.")
            }
            .alert("Nhắc khi rời quán quen", isPresented: $explainsAlwaysLocation) {
                Button("Tiếp tục") { setLeaveReminder(true) }
                Button("Để sau", role: .cancel) {}
            } message: {
                Text("Để biết lúc bạn rời một quán đã ghi từ 3 lần, Nhẩm cần quyền vị trí “Luôn luôn” và quyền gửi thông báo. Nhẩm chỉ theo dõi tối đa 20 nơi như vậy, xử lý ngay trên máy và không gửi vị trí đi đâu.")
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

    #if DEBUG
    /// Tạm thời, chỉ có ở bản Debug: tạo hoặc xóa dữ liệu mẫu để xem màn hình khi có nhiều ngày.
    private var sampleDataSection: some View {
        Section {
            Button("Tạo dữ liệu mẫu (90 ngày)".description) {
                let count = ExpenseRecorder(context: modelContext).insertSampleData(days: 90, now: Date(), calendar: calendar)
                sampleMessage = "Đã tạo \(count) khoản mẫu."
            }
            Button("Xóa dữ liệu mẫu".description, role: .destructive) {
                let count = ExpenseRecorder(context: modelContext).removeSampleData()
                sampleMessage = "Đã xóa \(count) khoản mẫu."
            }
        } header: {
            Text(verbatim: "Thử nghiệm (tạm thời)")
        } footer: {
            Text(verbatim: sampleMessage ?? "Chỉ có ở bản Debug. Khoản mẫu có đánh dấu riêng, xóa không đụng dữ liệu thật. Màn Hôm nay chỉ hiện 35 ngày gần nhất.")
        }
        .listRowBackground(Color.xuSurface)
    }
    #endif

    private func setLeaveReminder(_ isOn: Bool) {
        settings.leaveReminderEnabled = isOn
        Task {
            if isOn {
                _ = await NotificationManager.shared.requestAuthorization()
                location.requestAlways()
            }
            await PlaceMonitor.shared.refresh()
        }
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
