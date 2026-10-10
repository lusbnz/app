import SwiftUI

/// Nơi ghi của khoản đang gõ: hiện ngay khi mở ô gõ, không đợi ghi xong.
enum EntryPlaceState: Equatable {
    /// Chưa biết vị trí, hoặc chưa có tên cho chỗ này.
    case none
    case searching
    case named(String)
    /// Người dùng bỏ: lần ghi này không lưu vị trí.
    case removed

    var name: String? {
        if case .named(let name) = self { name } else { nil }
    }

    var savesLocation: Bool { self != .removed }
}

struct EntryPlaceChip: View {
    let state: EntryPlaceState
    let remove: () -> Void
    let restore: () -> Void

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang tìm nơi ghi")
            }
            .font(.footnote)
            .foregroundStyle(Color.xuTextSecondary)
            .frame(minHeight: 32)
        case .named(let name):
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                Text(name).lineLimit(1)
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.xuTextSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Không lưu nơi cho khoản này")
            }
            .font(.subheadline)
            .padding(.leading, 12)
            .padding(.trailing, 2)
            .frame(minHeight: 36)
            .background(Color.xuSurface, in: .capsule)
            .accessibilityElement(children: .contain)
        case .removed:
            Button(action: restore) {
                Label("Không lưu nơi cho khoản này. Hoàn lại", systemImage: "arrow.uturn.backward")
                    .font(.footnote)
                    .foregroundStyle(Color.xuTextSecondary)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        EntryPlaceChip(state: .named("Phở Thìn 13 Lò Đúc"), remove: {}, restore: {})
        EntryPlaceChip(state: .searching, remove: {}, restore: {})
        EntryPlaceChip(state: .removed, remove: {}, restore: {})
    }
    .padding()
    .xuScreen()
}
