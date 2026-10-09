import SwiftUI

/// Thanh nền đậm hiện 5 giây sau mỗi lần lưu (8 giây khi có cảnh báo hạn mức).
struct UndoBar: View {
    let batch: SavedBatch
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.summary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let warning = batch.warning {
                    Text(warning)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, batch.warning == nil ? 0 : 8)
            Spacer()
            Button("Hoàn tác", action: undo)
                .font(.subheadline.weight(.bold))
                .frame(minHeight: 44)
        }
        .foregroundStyle(Color.xuOnStrongSurface)
        .padding(.horizontal, 18)
        .background(Color.xuStrongSurface, in: .rect(cornerRadius: 26))
        .task(id: batch.batchID) {
            // Cảnh báo dài hơn nên cho thêm thời gian đọc.
            try? await Task.sleep(for: .seconds(batch.warning == nil ? 5 : 8))
            if !Task.isCancelled { dismiss() }
        }
    }
}

#Preview {
    UndoBar(batch: SavedBatch(batchID: UUID(), loanIDs: [], summary: "Đã ghi nhậu 115k", warning: nil), undo: {}, dismiss: {})
        .padding()
        .xuScreen()
}
