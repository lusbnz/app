# Ý tưởng để sau

Những thứ nằm ngoài tài liệu yêu cầu, chưa làm.

## Người dùng đã yêu cầu, đang chờ

Người dùng đã chọn làm các mục dưới đây (và đồng ý nới "không backend" riêng cho phần AI), nhưng chưa làm xong.

- **Tự ghi từ tin nhắn ngân hàng** qua Phím tắt, dùng lại intent ghi nhanh. Đã có: `BankMessageParser` (logic thuần, có test). Còn thiếu: `LogBankMessageIntent` (qua `SaveGate.canSave`), chống ghi trùng bằng mã băm tin nhắn, khớp ví theo từ khóa, mục hướng dẫn trong `ShortcutsGuideView`, nút dán tin nhắn ở ô gõ.
- **Nhiều ví** với số dư và chuyển tiền giữa các ví. Đã có: `WalletBalances` (logic thuần, có test). Còn thiếu: mô hình `Wallet` và `WalletTransfer`, `Expense.walletID`, màn hình ví và chuyển tiền, chọn ví ở ô gõ và khi sửa, mục "Số dư các ví" ở màn Tháng, lọc theo ví ở tìm kiếm.
- **Báo cáo năm và xuất PDF** (Pennyline Pro): `YearReport` (logic thuần) và màn hình, xuất bằng `ImageRenderer`.
- **Phát hiện khoản đăng ký** (Netflix, Spotify...) từ các khoản lặp, nhắc khi giá tăng (Pennyline Pro): `SubscriptionDetector` (logic thuần) và chỗ hiện ở Khoản định kỳ và màn Tháng.
- **Gói AI tách riêng**, tính theo lượt dùng mỗi tháng (Pennyline AI, có thể nạp thêm lượt): proxy Cloudflare Worker trong `Backend/` (xác thực bằng App Store Server API, hạn mức tháng bằng Durable Object, gọi Claude), phía app có `AIConfig` (chưa đặt địa chỉ thì ẩn hết giao diện AI), `AIClient`, hộp đồng ý gửi dữ liệu, mục AI trong Tùy chỉnh kèm số lượt còn lại; dùng cho nhận xét tháng, hỗ trợ tách khoản chi khó hiểu và trả lời Hỏi Pennyline bằng mô hình đám mây. Sản phẩm StoreKit riêng. Người dùng phải tự triển khai Worker và đặt khóa.

## Đã đề xuất, chưa được chọn

- Tìm khoản chi thêm theo: khoảng số tiền, trong hoặc ngoài ngân sách, chọn theo tên nơi, chỉ khoản chia tiền, và sắp xếp (mới nhất, cũ nhất, lớn nhất).
- Màu riêng cho danh mục tự thêm (hiện dùng chung màu "khác" ở biểu đồ Tháng).
- Nhắc nợ sau N ngày cho khoản ứng; nối chia tiền với sổ ứng.
- Chặn micro khi máy không nhận dạng tiếng Việt ngoại tuyến được (hiện hệ thống có thể gửi âm thanh lên máy chủ Apple).
- Khóa app có thời gian ân hạn (ví dụ 1 phút) trước khi khóa lại.
- Tiền tệ mặc định khác đồng, và nhập tỷ giá theo từng ngày.
- Cụm lệnh Siri và bộ tách khoản chi hiểu tiếng Anh ("pho 45k, coffee 3 usd").
- Sao lưu tự động chép thêm sang iCloud Drive khi dự án đã bật iCloud; sao lưu có mã hóa bằng mật khẩu; khôi phục kiểu thay thế toàn bộ (hiện chỉ hợp nhất).
- Nhập CSV: đối chiếu sao kê ngân hàng với khoản đã ghi tay (cùng ngày, số tiền khớp) thay vì chỉ bỏ dòng trùng, và tự tạo danh mục tự thêm từ tên cột danh mục lạ.
- Khoản định kỳ: chọn ngày bắt đầu cho chu kỳ hai tuần (hiện tính từ thứ đã chọn đầu tiên kể từ ngày tạo), hiện "Lần tới" ngay ở danh sách, ngày làm việc hoặc "ngày cuối tháng".
- Hỏi Pennyline nhớ ngữ cảnh qua nhiều câu và giữ lịch sử câu hỏi.
