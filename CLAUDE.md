# Xu

Sổ chi tiêu kiểu tin nhắn cho người Việt. iOS, SwiftUI và SwiftData.

## Ràng buộc

- iOS tối thiểu 18.0. Chỉ iPhone, chỉ dọc. API mới hơn phải bọc trong `if #available`.
- Swift 6, kiểm tra concurrency nghiêm ngặt. Dùng `@Observable` và `async/await`. Không dùng Combine, không dùng `ObservableObject`.
- Chỉ dùng framework của Apple: SwiftUI, SwiftData, WidgetKit, AppIntents, StoreKit 2, Vision, CoreLocation, UserNotifications, FoundationModels, Swift Testing. Không thư viện bên thứ ba, không backend, không analytics.
- Tiền lưu bằng `Int` đơn vị đồng. Không bao giờ dùng `Double` cho tiền.
- Mọi phép tính ngày nhận `Calendar` và `Date` làm tham số. Ở tầng giao diện lấy từ `Calendar.current`.
- Chuỗi giao diện bằng tiếng Việt, đặt trong `Xu/Localizable.xcstrings`.
- Bundle ID `com.quocviet.Xu`, App Group `group.com.quocviet.Xu`.
- Không sửa tay `Xu.xcodeproj/project.pbxproj`. Dự án dùng thư mục đồng bộ: tạo tệp `.swift` đúng thư mục là đủ. Việc cần thêm target hoặc capability thì dừng lại và hướng dẫn người dùng làm trong Xcode.

## Cấu trúc

```
Xu/
  App/            XuApp.swift, cấu hình ModelContainer, điều hướng gốc
  Models/         @Model của SwiftData
  Parsing/        bộ tách khoản chi
  Budget/         công thức ngân sách
  Formatting/     định dạng tiền kiểu "194k", "7,1tr"
  Suggestions/    gợi ý theo giờ và vị trí
  Receipt/        đọc hóa đơn bằng Vision
  Ask/            Hỏi Xu
  Features/       Onboarding/, Today/, Entry/, Detail/, Month/, Settings/, Paywall/
  Store/          StoreKit 2
  Intents/        App Intents
  Notifications/  nhắc 21:00, nhắc khi rời quán quen
  DesignSystem/   màu, font, HighlightedNumber
XuWidgets/        mã của target widget
XuTests/
```

- `Parsing`, `Budget`, `Formatting`, `Suggestions` là logic thuần: chỉ `import Foundation`, không phụ thuộc SwiftUI hay SwiftData, phải có unit test đầy đủ.
- View đọc dữ liệu bằng `@Query`, ghi qua `modelContext`. Mỗi View có `#Preview` với dữ liệu mẫu trong bộ nhớ.
- Mô hình SwiftData tương thích CloudKit: mọi thuộc tính có mặc định hoặc optional, không `@Attribute(.unique)`, quan hệ optional.
- Khóa của luật danh mục (`CategoryRule.keyword`, tham số `rules` của bộ tách) luôn chuẩn hóa bằng `TextNormalizer.keyword`.

## Kiểm tra

Chạy sau mỗi thay đổi đáng kể. Không báo xong khi build hoặc test còn lỗi.

```bash
xcodebuild -scheme Xu -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath build/DerivedData build
xcodebuild -scheme Xu -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath build/DerivedData test
```

Máy này có nhiều runtime máy ảo, nên phải ghi rõ `OS=`; chỉ ghi tên máy thì `xcodebuild` không tìm ra.

Khi máy đang nặng tải hoặc gần hết ổ đĩa, lệnh `test` có thể treo ở bước nhân bản máy ảo. Thêm `-parallel-testing-enabled NO` để test chạy thẳng trên máy ảo đã chọn.

Bản Debug nhận tham số khởi chạy để xem nhanh các màn hình trên máy ảo (xem `Xu/App/DebugLaunch.swift`), ví dụ:

```bash
xcrun simctl launch booted com.quocviet.Xu -demo -open month
```

## Cách làm việc

- Làm theo giai đoạn. Cuối mỗi giai đoạn: build và test xanh, một commit, tóm tắt, rồi dừng chờ xác nhận.
- Không thêm tính năng ngoài tài liệu yêu cầu. Ý tưởng mới ghi vào `IDEAS.md`.
- Không để lại `TODO` câm.
