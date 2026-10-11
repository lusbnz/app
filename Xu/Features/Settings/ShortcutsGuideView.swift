import SwiftUI

/// Trang hướng dẫn dùng Pennyline qua Siri, Phím tắt và Nút Tác vụ.
struct ShortcutsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                step(
                    "Siri",
                    "Nói “Ghi chi tiêu trong Pennyline”, Siri sẽ hỏi bạn tiêu gì. Trả lời như khi gõ: “phở 45k”."
                )
                step(
                    "Phím tắt",
                    "Mở app Phím tắt, tìm Pennyline. Có sẵn “Ghi chi tiêu”, “Ghi nhanh một khoản” và “Mở ô gõ” để bạn ghép vào phím tắt riêng."
                )
                step(
                    "Tin nhắn ngân hàng (Pennyline Pro)",
                    "Trong app Phím tắt, vào Tự động hóa, tạo mới “Tin nhắn”, chọn người gửi là ngân hàng của bạn và “Chạy ngay”. Thêm tác vụ “Ghi từ tin nhắn ngân hàng” của Pennyline, đưa “Nội dung tin nhắn” vào ô Tin nhắn. Từ đó mỗi tin báo trừ tiền thành một khoản chi; tin báo tiền vào được cộng vào ví có từ khóa khớp (đặt ở Tùy chỉnh, Ví). Cùng một tin nhắn không bao giờ bị ghi hai lần."
                )
                step(
                    "Nút Tác vụ",
                    "Vào Cài đặt, Nút Tác vụ, chọn Phím tắt rồi chọn “Mở ô gõ” của Pennyline. Bấm giữ nút là gõ được ngay."
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
