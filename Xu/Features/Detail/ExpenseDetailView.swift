import PhotosUI
import SwiftData
import SwiftUI

/// Chi tiết một khoản chi: xem, sửa, thêm ảnh, xóa.
struct ExpenseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query private var customCategories: [CustomCategory]
    @Bindable var expense: Expense
    @State private var isEditing = false
    @State private var fields = ExpenseFields()
    @State private var showsPhoto = false
    @State private var confirmsDelete = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var reapply: ReapplyOffer?
    @State private var showsPlacePicker = false

    private var recorder: ExpenseRecorder { ExpenseRecorder(context: modelContext) }
    private var image: UIImage? { expense.photo.flatMap(UIImage.init(data:)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image {
                        Button { showsPhoto = true } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ảnh hóa đơn")
                        .accessibilityHint("Xem toàn màn hình")
                    }
                    if isEditing {
                        ExpenseFieldsEditor(fields: $fields, onPickPlace: { showsPlacePicker = true })
                    } else {
                        summary
                        rows
                    }
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .xuScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Hủy" : "Đóng") {
                        if isEditing { isEditing = false } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("Xong", action: applyEdits)
                            .disabled(fields.amount == nil)
                    } else {
                        Button("Sửa", action: startEditing)
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $showsPlacePicker) {
            PlacePickerView(expense: expense, name: $fields.placeName, appliesToSiblings: $fields.appliesPlaceToSiblings)
        }
        .fullScreenCover(isPresented: $showsPhoto) {
            if let image { PhotoViewer(image: image) }
        }
        .reapplyDialog($reapply)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { picked in
                expense.photo = ImageCompressor.jpeg(from: picked)
                recorder.commit()
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Xóa khoản này?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Xóa khoản này", role: .destructive) {
                recorder.delete(expense)
                dismiss()
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    expense.photo = ImageCompressor.jpeg(from: data)
                    recorder.commit()
                }
                pickedPhoto = nil
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expense.displayName)
                .font(.title3)
            Text(MoneyFormatter.short(expense.amount))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .money(expense.amount)
            if let foreignNote = expense.foreignNote {
                Text(foreignNote)
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
            }
            if let splitNote = expense.splitNote {
                Text("phần của bạn · \(splitNote)")
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row("Danh mục", value: CategoryCatalog(custom: customCategories).info(for: expense.categoryKey).title)
            row("Thời gian", value: VietnameseDate.dayAndTime(expense.date, now: Date(), calendar: calendar))
            row("Nơi ghi", value: expense.placeName ?? (expense.latitude == nil
                ? String(localized: "không lưu")
                : String(localized: "đã lưu vị trí")))
            Toggle("Ngoài ngân sách", isOn: Binding {
                expense.isOutsideBudget
            } set: {
                expense.isOutsideBudget = $0
                recorder.commit()
            })
            .frame(minHeight: 52)
        }
    }

    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                Text(value)
                    .foregroundStyle(Color.xuTextSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            Divider().overlay(Color.xuDivider)
        }
    }

    private var actions: some View {
        let hasPhoto = expense.photo != nil
        let photoButtons = Group {
            if CameraPicker.isAvailable {
                Button(hasPhoto ? "Chụp lại" : "Chụp ảnh") { showsCamera = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text(CameraPicker.isAvailable ? "Chọn từ Ảnh" : (hasPhoto ? "Đổi ảnh" : "Thêm ảnh"))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        let deleteButton = Button("Xóa khoản này") { confirmsDelete = true }
            .buttonStyle(SecondaryButtonStyle())
        // Màn hẹp hoặc chữ lớn thì xuống hàng thay vì bị rớt chữ.
        return ViewThatFits(in: .horizontal) {
            HStack {
                photoButtons
                Spacer()
                deleteButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { photoButtons }
                deleteButton
            }
        }
        .padding(.top, 8)
    }

    private func startEditing() {
        fields = ExpenseFields(
            name: expense.name, amountText: ExpenseFields.amountText(for: expense.amount),
            categoryKey: expense.categoryKey, isOutsideBudget: expense.isOutsideBudget, date: expense.date,
            placeName: expense.placeName ?? ""
        )
        isEditing = true
    }

    private func applyEdits() {
        guard let amount = fields.amount else { return }
        expense.name = fields.name.trimmingCharacters(in: .whitespaces)
        if amount != expense.amount {
            expense.amount = amount
            expense.originalAmount = nil
            expense.splitCount = nil
            expense.foreignAmount = nil
        }
        let changedCategory = fields.categoryKey != expense.categoryKey
        if changedCategory {
            expense.categoryKey = fields.categoryKey
            recorder.teach(name: expense.name, categoryKey: fields.categoryKey)
        }
        expense.isOutsideBudget = fields.isOutsideBudget
        expense.date = fields.date
        // Tên nơi sửa cùng lúc với các trường khác, và có thể đổi theo cho các khoản khác ở cùng chỗ.
        let newPlace = PlaceNaming.clean(fields.placeName)
        if newPlace != PlaceNaming.clean(expense.placeName) {
            recorder.setPlace(of: expense, to: newPlace, applyingToSiblings: fields.appliesPlaceToSiblings)
        }
        recorder.commit()
        if changedCategory {
            reapply = recorder.reapplyOffer(keyword: expense.name, categoryKey: fields.categoryKey)
        }
        isEditing = false
    }
}

#Preview {
    ExpenseDetailView(expense: PreviewData.expense).xuPreview()
}
