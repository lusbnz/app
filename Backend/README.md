# Pennyline AI (Cloudflare Worker)

Proxy nhỏ đứng giữa app và Claude. Nó giữ khóa API của Anthropic, hỏi Apple xem gói Pennyline AI của người gọi còn hiệu lực không, và đếm lượt dùng theo tháng. Nó không lưu nội dung người dùng gửi, chỉ lưu bộ đếm lượt theo mã đăng ký.

App chỉ gọi tới đây khi cả ba điều đúng: đã đặt địa chỉ Worker trong `Xu/App/AIClient.swift` (`AIConfig.productionURL`), người dùng đã mua gói `xu.ai.monthly`, và đã bật công tắc đồng ý. Chưa đặt địa chỉ thì mọi giao diện AI trong app đều ẩn.

## Đường gọi

Mọi yêu cầu (trừ `/`) mang header `X-Pennyline-Transaction: <mã giao dịch của gói AI>`.

| Đường | Việc |
| --- | --- |
| `GET /v1/quota` | Số lượt đã dùng, giới hạn, lượt nạp thêm, ngày làm mới |
| `POST /v1/run` | `{task, sheet?, text?, language?}` với `task` là `ask`, `insight` hoặc `normalize`; trừ một lượt, trả `{text, quota}` |
| `POST /v1/topup` | `{transactionId}` của một lần mua `xu.ai.topup`; kiểm với Apple rồi cộng lượt, mỗi giao dịch một lần |

Lỗi: 401 thiếu mã, 403 không có gói còn hiệu lực, 429 hết lượt, 502 mô hình lỗi (lượt được trả lại).

`normalize` dùng `claude-haiku-5-5`; `ask` và `insight` dùng `claude-sonnet-5-5`. Đổi ở `src/prompts.ts`.

## Triển khai

Cần tài khoản Cloudflare (gói có Durable Objects), khóa API của Anthropic, và một khóa In-App Purchase của App Store Connect (Users and Access, Integrations, In-App Purchase): ghi lại Issuer ID, Key ID và tải tệp `.p8`.

```bash
cd Backend
npm install
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APPLE_ISSUER_ID
npx wrangler secret put APPLE_KEY_ID
npx wrangler secret put APPLE_PRIVATE_KEY   # dán cả nội dung tệp .p8
npx wrangler deploy
```

Trong `wrangler.toml`: để `APPLE_ENVIRONMENT = "sandbox"` khi thử bằng Xcode hoặc TestFlight, đổi thành `"production"` khi lên App Store. `MONTHLY_LIMIT` và `TOPUP_CREDITS` là số lượt của gói và của mỗi lần nạp.

Sau khi triển khai:

1. Điền địa chỉ Worker vào `AIConfig.productionURL`.
2. Tạo hai sản phẩm trong App Store Connect: gói tự gia hạn `xu.ai.monthly` (nhóm riêng, tách khỏi Pennyline Pro) và sản phẩm tiêu hao `xu.ai.topup`. Tệp thử `XuTests/Xu.storekit` đã có cả hai.
3. Cập nhật nhãn quyền riêng tư của app: số liệu chi tiêu đã gộp được gửi tới máy chủ của bạn và tới Anthropic khi người dùng bật gói AI.

Thử cục bộ: `npx wrangler dev`, rồi chạy app với tham số `-aiBaseURL http://localhost:8787` (chỉ bản Debug). Giao dịch do tệp `.storekit` cục bộ tạo ra không có trên máy chủ của Apple, nên Worker sẽ trả 403; muốn thử trọn đường phải dùng tài khoản sandbox.

## Kiểm tra

```bash
npm run check   # kiểm kiểu
npm test        # test phần tính hạn mức, ký JWT, đọc trạng thái gói, dựng yêu cầu
```

Phần gọi Apple và Anthropic thật chưa được chạy thử ở đâu: chỉ các hàm thuần có test.

## Giới hạn đã biết

- Worker nhận diện người dùng bằng mã giao dịch, không kiểm chữ ký JWS do app gửi. Ai biết mã giao dịch của người khác thì dùng được lượt của họ (không đọc được dữ liệu gì, vì Worker không lưu nội dung). Muốn chặt hơn thì cho app gửi JWS và kiểm chuỗi chứng chỉ của Apple.
- Mỗi yêu cầu hỏi Apple một lần. Lượng dùng lớn thì nên nhớ kết quả vài phút trong Durable Object.
