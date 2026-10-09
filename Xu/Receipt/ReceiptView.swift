import PhotosUI
import SwiftData
import SwiftUI

/// Chụp hóa đơn: đọc tổng tiền và ngày giờ ngay trên máy, cho sửa, rồi Ghi kèm ảnh.
struct ReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @Query private var expenses: [Expense]
    @Query private var rules: [CategoryRule]
    @State private var image: UIImage?
    @State private var fields = ExpenseFields()
    @State private var isReading = false
    @State private var hasReceiptDate = false
    @State private var showsCamera = false
    @State private var showsEditor = false
    @State private var pickedPhoto: PhotosPickerItem?

    let now: Date

    init(now: Date, image: UIImage? = nil) {
        self.now = now
        _image = State(initialValue: image)
        let since = Calendar.current.date(byAdding: .day, value: -35, to: now) ?? now
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= since })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    impact
                    if let image {
                        reading(image)
                    } else {
                        Text("Chụp hoặc chọn một ảnh hóa đơn. Xu sẽ đọc tổng tiền và ngày giờ.")
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    Text("Ảnh được đọc ngay trên máy và lưu kèm khoản chi để bạn xem lại.")
                        .font(.footnote)
                        .foregroundStyle(Color.xuTextSecondary)
                    HStack {
                        if CameraPicker.isAvailable {
                            Button(image == nil ? "Chụp ảnh" : "Chụp lại") { showsCamera = true }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Text("Chọn từ Ảnh")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .xuScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ghi", action: save)
                        .disabled(image == nil || isReading || fields.amount == nil)
                }
            }
        }
        .fontDesign(.rounded)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { use($0) }.ignoresSafeArea()
        }
        .sheet(isPresented: $showsEditor) {
            editor
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    use(picked)
                }
                pickedPhoto = nil
            }
        }
        .task {
            if let image {
                await read(image)
            } else if CameraPicker.isAvailable {
                showsCamera = true
            }
        }
    }

    // MARK: - Tác động lên hôm nay

    private var impact: some View {
        var entries = expenses.map(\.budgetEntry)
        if let amount = fields.amount {
            entries.append(BudgetEntry(amount: amount, date: fields.date, isOutsideBudget: fields.isOutsideBudget))
        }
        let status = BudgetCalculator.status(
            monthlyBudget: settings.monthlyBudget, entries: entries, now: now, calendar: calendar
        )
        return VStack(alignment: .leading, spacing: 2) {
            HighlightedNumber(text: MoneyFormatter.short(status.remainingToday), fraction: status.todayFraction, size: 44)
            Text(fields.amount == nil ? "còn được tiêu hôm nay" : "còn lại hôm nay sau khi ghi")
                .font(.footnote)
                .foregroundStyle(Color.xuTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hôm nay còn \(MoneyFormatter.spoken(status.remainingToday))")
    }

    // MARK: - Kết quả đọc

    private func reading(_ image: UIImage) -> some View {
        Button { showsEditor = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 128)
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityLabel("Ảnh hóa đơn")
                    if isReading {
                        ProgressView("Đang đọc hóa đơn")
                            .frame(maxWidth: .infinity, minHeight: 128)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fields.name.isEmpty ? String(localized: "hóa đơn") : fields.name)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text(SpendingCategory(key: fields.categoryKey).title)
                                if fields.isOutsideBudget { ButterLabel(text: "ngoài ngân sách") }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.xuTextSecondary)
                            if let amount = fields.amount {
                                Text(MoneyFormatter.short(amount))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .money(amount)
                            } else {
                                Text("Chưa đọc được tổng tiền, chạm để điền")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.xuTextSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !isReading {
                    let day = VietnameseDate.dayAndTime(fields.date, now: Date(), calendar: calendar)
                    Text(hasReceiptDate ? "Ngày trên hóa đơn: \(day)" : "Thời gian: \(day)")
                        .font(.subheadline)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Chạm để sửa")
    }

    private var editor: some View {
        NavigationStack {
            ScrollView {
                ExpenseFieldsEditor(fields: $fields)
                    .padding(.horizontal, 24)
            }
            .xuScreen()
            .navigationTitle("Sửa khoản chi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showsEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fontDesign(.rounded)
    }

    // MARK: - Đọc và lưu

    private func use(_ picked: UIImage) {
        image = picked
        Task { await read(picked) }
    }

    private func read(_ image: UIImage) async {
        isReading = true
        defer { isReading = false }
        let lines = (try? await ReceiptReader.lines(in: image)) ?? []
        let reading = ReceiptParser.parse(lines: lines, now: Date(), calendar: calendar)
        let allowance = BudgetCalculator.status(
            monthlyBudget: settings.monthlyBudget, entries: expenses.map(\.budgetEntry), now: now, calendar: calendar
        ).allowanceToday
        hasReceiptDate = reading.date != nil
        fields = ExpenseFields(
            name: reading.merchant,
            amountText: ExpenseFields.amountText(for: reading.total),
            categoryKey: CategoryClassifier.categoryKey(for: reading.merchant, rules: rules.lookup),
            isOutsideBudget: reading.total.map { ExpenseParser.isOutsideBudget(amount: $0, dailyAllowance: allowance) } ?? false,
            date: reading.date ?? Date()
        )
    }

    private func save() {
        guard let image, let amount = fields.amount else { return }
        let name = fields.name.trimmingCharacters(in: .whitespaces)
        var info = RecordContext(rawText: name, date: fields.date, photo: ImageCompressor.jpeg(from: image))
        // Vị trí hiện tại chỉ đúng với hóa đơn của hôm nay.
        if settings.suggestionsEnabled, calendar.isDateInToday(fields.date), let coordinate = location.freshCoordinate {
            info.latitude = coordinate.latitude
            info.longitude = coordinate.longitude
        }
        let draft = ExpenseDraft(
            name: name, amount: amount, categoryKey: fields.categoryKey, isOutsideBudget: fields.isOutsideBudget
        )
        let batch = ExpenseRecorder(context: modelContext).record([.expense(draft)], in: info)
        appState.didSave(batch)
        dismiss()
    }
}

#Preview {
    ReceiptView(now: Date(), image: SampleReceipt.image()).xuPreview()
}
