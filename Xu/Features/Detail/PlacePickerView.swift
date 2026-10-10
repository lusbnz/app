import SwiftData
import SwiftUI

/// Chọn tên nơi ghi cho một khoản đang sửa: gõ tay, chọn tên đã dùng quanh đây, hoặc tìm quán gần đó (gửi vị trí cho Apple).
/// Chỉ ghi vào `name` và `appliesToSiblings`; việc lưu vào khoản làm ở nút "Xong" của màn Chi tiết, cùng các trường khác.
struct PlacePickerView: View {
    private enum SearchState { case idle, searching, found, empty }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    let expense: Expense
    @Binding var name: String
    @Binding var appliesToSiblings: Bool
    @State private var text = ""
    @State private var candidates: [PlaceCandidate] = []
    @State private var search = SearchState.idle
    @State private var usedNearby: [String] = []
    @State private var siblings = 0
    @State private var applies = true

    private var coordinate: Coordinate? {
        guard let latitude = expense.latitude, let longitude = expense.longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private var recorder: ExpenseRecorder { ExpenseRecorder(context: modelContext) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên nơi") {
                    TextField("Quán phở Thìn", text: $text)
                        .submitLabel(.done)
                        .onSubmit(save)
                    if !text.isEmpty {
                        Button("Bỏ tên nơi", role: .destructive) {
                            text = ""
                            save()
                        }
                    }
                }
                .listRowBackground(Color.xuSurface)
                if !usedNearby.isEmpty {
                    Section("Đã dùng quanh đây") {
                        ForEach(usedNearby, id: \.self) { name in
                            Button(name) { text = name }
                                .foregroundStyle(Color.xuTextPrimary)
                        }
                    }
                    .listRowBackground(Color.xuSurface)
                }
                nearbySection
                if siblings > 0 {
                    Section {
                        Toggle("Áp cho \(siblings) khoản khác ở cùng chỗ", isOn: $applies)
                    }
                    .listRowBackground(Color.xuSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle("Nơi ghi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Xong", action: save) }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
        .fontDesign(.rounded)
    }

    @ViewBuilder
    private var nearbySection: some View {
        if coordinate != nil {
            Section {
                switch search {
                case .idle:
                    Button("Tìm quán gần đây", action: findNearby)
                case .searching:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Đang tìm quán gần đây")
                    }
                case .empty:
                    Text("Không tìm thấy quán nào ở gần đây.").foregroundStyle(Color.xuTextSecondary)
                    Button("Thử lại", action: findNearby)
                case .found:
                    ForEach(candidates) { candidate in
                        Button(candidate.name) { text = candidate.name }
                            .foregroundStyle(Color.xuTextPrimary)
                    }
                }
            } header: {
                Text("Quán gần đây")
            } footer: {
                if search == .idle {
                    Text("Tìm quán sẽ gửi vị trí của khoản này cho Apple.")
                }
            }
            .listRowBackground(Color.xuSurface)
        } else {
            Section {
            } footer: {
                Text("Khoản này không có vị trí nên chỉ đặt tên tay được.")
            }
        }
    }

    private func load() {
        text = name
        applies = appliesToSiblings
        siblings = recorder.siblingCount(of: expense)
        if let coordinate {
            usedNearby = PlaceNaming.nearbyNames(near: coordinate, in: recorder.namedPlaces())
            // Đã đồng ý gửi vị trí cho Apple ở Tùy chỉnh thì tự tìm, không bắt bấm.
            if settings.placeLookupEnabled { findNearby() }
        }
    }

    private func findNearby() {
        guard let coordinate else { return }
        search = .searching
        Task {
            let found = PlaceNaming.ranked(await PlaceLookup.shared.searcher.candidates(near: coordinate), near: coordinate)
            candidates = found
            search = found.isEmpty ? .empty : .found
        }
    }

    private func save() {
        name = text
        appliesToSiblings = applies && siblings > 0
        dismiss()
    }
}
