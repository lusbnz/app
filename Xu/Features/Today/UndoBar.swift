import SwiftUI

/// Thanh nền đậm hiện 5 giây sau mỗi lần lưu.
struct UndoBar: View {
    let batch: SavedBatch
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(batch.summary)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Button("Hoàn tác", action: undo)
                .font(.subheadline.weight(.bold))
                .frame(minHeight: 44)
        }
        .foregroundStyle(Color.xuOnStrongSurface)
        .padding(.horizontal, 18)
        .background(Color.xuStrongSurface, in: .capsule)
        .task(id: batch.batchID) {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { dismiss() }
        }
    }
}

#Preview {
    UndoBar(batch: SavedBatch(batchID: UUID(), loanIDs: [], summary: "Đã ghi nhậu 115k"), undo: {}, dismiss: {})
        .padding()
        .xuScreen()
}
