import SwiftUI

/// Trang hướng dẫn dùng Nhẩm qua Siri, Phím tắt và Nút Tác vụ.
struct ShortcutsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                step(
                    "Siri",
                    "Nói “Ghi chi tiêu trong Nhẩm”, Siri sẽ hỏi bạn tiêu gì. Trả lời như khi gõ: “phở 45k”."
                )
                step(
                    "Phím tắt",
                    "Mở app Phím tắt, tìm Nhẩm. Có sẵn “Ghi chi tiêu”, “Ghi nhanh một khoản” và “Mở ô gõ” để bạn ghép vào phím tắt riêng."
                )
                step(
                    "Nút Tác vụ",
                    "Vào Cài đặt, Nút Tác vụ, chọn Phím tắt rồi chọn “Mở ô gõ” của Nhẩm. Bấm giữ nút là gõ được ngay."
                )
            }
            .padding(24)
        }
        .xuScreen()
        .navigationTitle("Siri, Phím tắt và Nút Tác vụ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).foregroundStyle(Color.xuTextSecondary)
        }
    }
}

#Preview {
    NavigationStack { ShortcutsGuideView() }.xuPreview()
}
