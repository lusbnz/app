# Ý tưởng để sau

Những thứ nằm ngoài tài liệu yêu cầu, chưa làm.

## Người dùng đã yêu cầu, đang chờ

(Không có.)

## Việc sau khi publish

Người dùng muốn để sau khi app đã lên App Store mới làm. Cho tới lúc đó gói Pennyline AI vẫn ẩn (`AIConfig.productionURL` là nil).

- Bật Pennyline AI:
  1. Triển khai Worker theo `Backend/README.md`: cần tài khoản Cloudflare, khóa API Anthropic và khóa In-App Purchase của App Store Connect.
  2. Điền địa chỉ Worker vào `AIConfig.productionURL` trong `Xu/App/AIClient.swift`.
  3. Tạo hai sản phẩm trong App Store Connect: `xu.ai.monthly` (gói tự gia hạn, nhóm riêng) và `xu.ai.topup` (tiêu hao). Giá trong tệp thử (39k và 19k) là giá tạm, chỉnh theo ý.
  4. Cập nhật nhãn quyền riêng tư của app trên App Store, vì số liệu gộp sẽ được gửi tới máy chủ riêng và Anthropic.
  5. Chạy thử trọn đường với tài khoản sandbox: phần gọi Apple và Anthropic thật chưa chạy lần nào.

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
- Khoản đăng ký: mục tổng hợp ở màn Tháng, nhận cả chu kỳ hai tuần và mỗi quý.
- Báo cáo năm: so từng danh mục với năm trước, thêm mục tiêu tiết kiệm và sổ ứng vào bản PDF.
- Ví: lọc theo ví ở tìm kiếm, nút dán tin nhắn ngân hàng ở ô gõ, khoản định kỳ gắn ví, điều chỉnh số dư cho khớp thực tế.
- Pennyline AI: kiểm chữ ký JWS của Apple ở Worker thay vì chỉ tra mã giao dịch, nhớ kết quả kiểm gói vài phút, cho mô hình gọi công cụ cục bộ thay vì nhận cả bảng số liệu, đọc ảnh hóa đơn khó (cần đổi cam kết không gửi ảnh).
