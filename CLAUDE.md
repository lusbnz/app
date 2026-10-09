# Xu

Sổ chi tiêu kiểu tin nhắn cho người Việt. iOS, SwiftUI và SwiftData.

## Ràng buộc

- iOS tối thiểu 18.0. Chỉ iPhone, chỉ dọc. API mới hơn phải bọc trong `if #available`.
- Swift 6, kiểm tra concurrency nghiêm ngặt. Dùng `@Observable` và `async/await`. Không dùng Combine, không dùng `ObservableObject`.
- Chỉ dùng framework của Apple: SwiftUI, SwiftData, WidgetKit, AppIntents, StoreKit 2, Vision, CoreLocation, UserNotifications, FoundationModels, Speech, AVFoundation (chỉ để thu âm đưa vào Speech), Swift Testing. Không thư viện bên thứ ba, không backend, không analytics.
- Tiền lưu bằng `Int` đơn vị đồng. Không bao giờ dùng `Double` cho tiền.
- Mọi phép tính ngày nhận `Calendar` và `Date` làm tham số. Ở tầng giao diện lấy từ `Calendar.current`.
- Chuỗi giao diện bằng tiếng Việt, đặt trong `Xu/Localizable.xcstrings`.
- Bundle ID `com.quocviet.Xu`, App Group `group.com.quocviet.Xu`.
- Không sửa tay `Xu.xcodeproj/project.pbxproj`. Dự án dùng thư mục đồng bộ: tạo tệp `.swift` đúng thư mục là đủ. Việc cần thêm target hoặc capability thì dừng lại và hướng dẫn người dùng làm trong Xcode. Ngoại lệ đã được người dùng cho phép một lần: hai khóa `INFOPLIST_KEY_NSMicrophoneUsageDescription` và `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` cho giọng nói. Khóa quyền mới nào khác vẫn phải hỏi trước.
- Chưa có target widget, chưa bật App Group và iCloud: những việc này người dùng làm trong Xcode. `XuStore` phải chạy được khi thiếu chúng (lùi về Application Support).

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
  Voice/          nhập khoản chi bằng giọng nói (Speech)
  DesignSystem/   màu, font, HighlightedNumber
XuWidgets/        mã của target widget
XuTests/
```

- `Parsing`, `Budget`, `Formatting`, `Suggestions` là logic thuần: chỉ `import Foundation`, không phụ thuộc SwiftUI hay SwiftData, phải có unit test đầy đủ.
- View đọc dữ liệu bằng `@Query`, ghi qua `modelContext`. Mỗi View có `#Preview` với dữ liệu mẫu trong bộ nhớ.
- Mô hình SwiftData tương thích CloudKit: mọi thuộc tính có mặc định hoặc optional, không `@Attribute(.unique)`, quan hệ optional.
- Khóa của luật danh mục (`CategoryRule.keyword`, tham số `rules` của bộ tách) luôn chuẩn hóa bằng `TextNormalizer.keyword`.

## Quy ước theo tính năng

- **Xu Pro:** chỉ bỏ giới hạn 5 lần ghi mỗi ngày của bản miễn phí (`SaveGate`, `SaveQuota`). Chụp hóa đơn, Hỏi Xu và widget màn hình khóa miễn phí cho mọi người. Mọi đường ghi (ô gõ, intent, widget, thông báo, vuốt "Ghi lại") đều phải qua `SaveGate.canSave`.
- **Danh mục:** có sẵn là `SpendingCategory`, tự thêm là `CustomCategory` với khóa `custom-<uuid>` (không đổi khi đổi tên). Giao diện luôn tra bằng `CategoryCatalog` (đọc `@Query CustomCategory`), không gọi `SpendingCategory(key:).title` trực tiếp. Khóa không còn tồn tại hiện là "khác". Xóa danh mục chuyển các khoản về "khác" và xóa luật trỏ tới nó (`ExpenseRecorder.deleteCategory`). Tên danh mục kiểm tra bằng `CategoryNaming`.
- **Thao tác nhanh:** danh sách khoản chi ở màn Hôm nay vuốt phải để "Ghi lại" và bật tắt "Ngoài ngân sách", vuốt trái để xóa và đổi danh mục. Logic nằm trong `ExpenseRecorder` (`repeatExpense`, `setCategory`, `toggleOutsideBudget`), không đặt trong View.
- **Giọng nói (`Voice/`):** `VoiceInput` chỉ thu âm và trả chữ, ưu tiên nhận dạng trên máy. Đổi số đọc bằng chữ ("bốn mươi lăm nghìn") thành chữ số là việc của `SpokenNumbers` (logic thuần, trong `Parsing/`). Chữ nói ra chỉ điền vào ô gõ, không tự ghi. Nút micro ẩn khi thiếu hai khóa quyền. Closure chạy trên luồng âm thanh phải tạo trong hàm `nonisolated`, nếu không sẽ crash do bị gắn `@MainActor`.
- **Bộ tách khoản chi:** hiểu `45k`, `45k5`, `45k rưỡi`, `1 triệu rưỡi`, `1 củ 2`, `chia 4`, `chia ba`, `chia tư`, `/4`. Thêm cách gõ mới thì thêm test vào `AmountParsingTests` hoặc `ExpenseParserTests`.
- **Biểu tượng app:** `Xu/Assets.xcassets/AppIcon.appiconset` có bản sáng và bản tối, 1024×1024, không kênh alpha. Chữ "xu" tím than trên vệt highlight vàng bơ, cùng bảng màu `XuTextPrimary`, `XuHighlight`, `XuButton`.

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

## Kiểm thử SwiftData

Test dùng `XuStore.inMemory()` phải giữ `ModelContainer` sống suốt bài test (ví dụ `defer { withExtendedLifetime(container) {} }`). Chỉ giữ `ModelContext` thì container bị giải phóng và test crash. Test có gọi `ExpenseRecorder.record` nên lưu và khôi phục `SaveGate.quota`, vì bộ đếm nằm trong App Group dùng chung giữa các lần chạy.
