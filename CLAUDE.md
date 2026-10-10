# Xu

Sổ chi tiêu kiểu tin nhắn cho người Việt. iOS, SwiftUI và SwiftData.

## Ràng buộc

- iOS tối thiểu 18.0. Chỉ iPhone, chỉ dọc. API mới hơn phải bọc trong `if #available`.
- Swift 6, kiểm tra concurrency nghiêm ngặt. Dùng `@Observable` và `async/await`. Không dùng Combine, không dùng `ObservableObject`.
- Chỉ dùng framework của Apple: SwiftUI, SwiftData, AppIntents, StoreKit 2, Vision, CoreLocation, UserNotifications, FoundationModels, Speech, AVFoundation (chỉ để thu âm đưa vào Speech), Swift Testing. Không thư viện bên thứ ba, không backend, không analytics.
- Tiền lưu bằng `Int` đơn vị đồng. Không bao giờ dùng `Double` cho tiền.
- Mọi phép tính ngày nhận `Calendar` và `Date` làm tham số. Ở tầng giao diện lấy từ `Calendar.current`.
- Chuỗi giao diện bằng tiếng Việt, đặt trong `Xu/Localizable.xcstrings`.
- Bundle ID `com.quocviet.Xu`, App Group `group.com.quocviet.Xu`.
- Không sửa tay `Xu.xcodeproj/project.pbxproj`. Dự án dùng thư mục đồng bộ: tạo tệp `.swift` đúng thư mục là đủ. Việc cần thêm target hoặc capability thì dừng lại và hướng dẫn người dùng làm trong Xcode. Ngoại lệ đã được người dùng cho phép, mỗi khóa một lần: `INFOPLIST_KEY_NSMicrophoneUsageDescription` và `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` (giọng nói), `INFOPLIST_KEY_NSCameraUsageDescription` (chụp ảnh). Khóa quyền mới nào khác vẫn phải hỏi trước.
- Chưa bật App Group và iCloud: những việc này người dùng làm trong Xcode. `XuStore` phải chạy được khi thiếu chúng (lùi về Application Support).

## Cấu trúc

```
Xu/
  App/            XuApp.swift, cấu hình ModelContainer, điều hướng gốc
  Models/         @Model của SwiftData
  Parsing/        bộ tách khoản chi
  Budget/         công thức ngân sách
  Formatting/     định dạng tiền kiểu "194k", "7,1tr"
  Suggestions/    gợi ý theo giờ và vị trí
  Search/         điều kiện tìm và lọc khoản chi (ExpenseFilter)
  Export/         xuất CSV (CSVExporter)
  Currency/       ngoại tệ và tỷ giá (Currency, ForeignAmountParser)
  Recurring/      lịch khoản định kỳ (RecurringPlanner)
  Receipt/        đọc hóa đơn bằng Vision
  Ask/            Hỏi Xu
  Features/       Onboarding/, Today/, Entry/, Detail/, Month/, Search/, Recurring/, Settings/, Paywall/
  Store/          StoreKit 2
  Intents/        App Intents
  Notifications/  nhắc 21:00, nhắc khi rời quán quen
  Voice/          nhập khoản chi bằng giọng nói (Speech)
  DesignSystem/   màu, font, HighlightedNumber
XuTests/
```

- `Parsing`, `Budget`, `Formatting`, `Suggestions`, `Search`, `Recurring`, `Export`, `Currency` là logic thuần: chỉ `import Foundation`, không phụ thuộc SwiftUI hay SwiftData, phải có unit test đầy đủ.
- View đọc dữ liệu bằng `@Query`, ghi qua `modelContext`. Mỗi View có `#Preview` với dữ liệu mẫu trong bộ nhớ.
- Mô hình SwiftData tương thích CloudKit: mọi thuộc tính có mặc định hoặc optional, không `@Attribute(.unique)`, quan hệ optional.
- Khóa của luật danh mục (`CategoryRule.keyword`, tham số `rules` của bộ tách) luôn chuẩn hóa bằng `TextNormalizer.keyword`.

## Quy ước theo tính năng

- **Xu Pro:** chỉ bỏ giới hạn 5 lần ghi mỗi ngày của bản miễn phí (`SaveGate`, `SaveQuota`). Chụp hóa đơn và Hỏi Xu miễn phí cho mọi người. Mọi đường ghi (ô gõ, intent, thông báo, vuốt "Ghi lại") đều phải qua `SaveGate.canSave`.
- **Danh mục:** có sẵn là `SpendingCategory`, tự thêm là `CustomCategory` với khóa `custom-<uuid>` (không đổi khi đổi tên). Giao diện luôn tra bằng `CategoryCatalog` (đọc `@Query CustomCategory`), không gọi `SpendingCategory(key:).title` trực tiếp. Mỗi danh mục có biểu tượng SF Symbol (`CategoryInfo.symbol`, hiện bằng `CategoryLabel`; logic thuần `CategoryIcon` trong `Parsing/`, test `CategoryIconTests`): có sẵn thì cố định, tự thêm thì lưu ở `CustomCategory.iconName` (rỗng thì dùng `tag`), chọn từ `CategoryIcon.palette` và được gợi ý theo tên. Biểu tượng chỉ để nhìn, VoiceOver chỉ đọc tên. Khóa không còn tồn tại hiện là "khác". Xóa danh mục chuyển các khoản về "khác" và xóa luật trỏ tới nó (`ExpenseRecorder.deleteCategory`). Tên danh mục kiểm tra bằng `CategoryNaming`. Đổi danh mục của một khoản (vuốt, Chi tiết, thêm hoặc sửa luật) thì hỏi có áp cho các khoản cũ cùng từ khóa không (`ReapplyOffer`, `reapplyDialog`); luật dài hơn vẫn thắng luật ngắn.
- **Thao tác nhanh:** danh sách khoản chi ở màn Hôm nay vuốt phải để "Ghi lại" và bật tắt "Ngoài ngân sách", vuốt trái để xóa và đổi danh mục. Logic nằm trong `ExpenseRecorder` (`repeatExpense`, `setCategory`, `toggleOutsideBudget`), không đặt trong View.
- **Giọng nói (`Voice/`):** `VoiceInput` chỉ thu âm và trả chữ, ưu tiên nhận dạng trên máy. Đổi số đọc bằng chữ ("bốn mươi lăm nghìn") thành chữ số là việc của `SpokenNumbers` (logic thuần, trong `Parsing/`). Chữ nói ra chỉ điền vào ô gõ, không tự ghi. Nút micro ẩn khi thiếu hai khóa quyền. Closure chạy trên luồng âm thanh phải tạo trong hàm `nonisolated`, nếu không sẽ crash do bị gắn `@MainActor`.
- **Tìm và lọc:** nút kính lúp ở màn Hôm nay mở `SearchView` (sheet). Tìm theo tên không phân biệt dấu và hoa thường, mọi từ gõ vào phải có trong tên; lọc theo nhiều danh mục và khoảng ngày (`DatePreset`). Quét toàn bộ khoản chi, không bị giới hạn 35 ngày. Logic nằm ở `ExpenseFilter`, test ở `ExpenseFilterTests`.
- **Khoản định kỳ:** `RecurringExpense` (tiền nhà, Netflix, gửi xe) lặp theo `RecurringFrequency`: hàng tuần (`weekday`, theo `Calendar.weekday`), hàng tháng (`dayOfMonth`, tháng ngắn thì lùi về ngày cuối), hàng năm (`monthOfYear` và `dayOfMonth`, 29/2 lùi về 28). Mặc định Xu chỉ nhắc: đến hạn thì hiện `DueRecurringRow` ở màn Hôm nay (Ghi hoặc Bỏ qua) và thông báo 9:00 có nút Ghi, Bỏ qua. Khoản bật `autoRecord` thì Xu tự ghi khi mở app (`RootView` gọi `ExpenseRecorder.recordAutomaticRecurring` lúc vào app và khi app active), dừng khi hết lượt ghi miễn phí trong ngày; lần ghi cuối hiện ở thanh Hoàn tác. `handledMonth` giữ tên cũ cho khớp dữ liệu đã lưu nhưng là mã kỳ đã xử lý (`RecurringPlanner.periodKey`: "2026-10" tháng, "2026-W41" tuần, "2026" năm); đổi tần suất thì xóa nó. Khoản tạo sau ngày đến hạn của kỳ này chờ kỳ sau. Lịch nằm trong `RecurringPlanner` (logic thuần), ghi và bỏ qua trong `ExpenseRecorder+Plans`, và vẫn qua `SaveGate.canSave`. Mã thông báo nhắc theo ngày (`dayKey`) vì khoản theo tuần có nhiều lần một tháng. `NotificationManager` luôn đặt lại gộp nhóm hành động của quán quen lẫn của khoản định kỳ vì `setNotificationCategories` thay cả bộ.
- **Hạn mức danh mục:** `CategoryBudget` đặt hạn mức tháng cho từng danh mục, luôn dùng để cảnh báo. Công tắc `AppSettings.limitsShapeDaily` (mặc định tắt, ở Tùy chỉnh > Ngân sách) cho hạn mức tính vào hạn mức ngày: `BudgetCalculator.status(...categoryLimits:...)` giữ riêng tiền của từng danh mục (ngân sách tự do = ngân sách trừ tổng hạn mức), khoản chi trong hạn mức không làm "còn được tiêu hôm nay" tụt (`BudgetStatus.countedToday`), phần vượt hạn mức thì trừ vào hạn mức chung; tổng đã tiêu và còn lại của tháng vẫn là số thật. Chỉ chỗ hiển thị (Hôm nay, ô gõ, Hóa đơn) dùng bản này qua `settings.dailyLimits(budgets)`; ngưỡng "ngoài ngân sách" và `ExpenseRecorder.status` vẫn dùng bản thường. `BudgetEntry.categoryKey` phải được điền. Từ 80% là "gần chạm", vượt hẳn mới là "vượt" (`CategoryBudgetCalculator`, logic thuần trong `Budget/`). Cảnh báo hiện ở `UndoBar` khi một lần ghi làm danh mục xấu đi (`SavedBatch.warning`, khoản ngoài ngân sách và khoản ngoài tháng này không tính) và ở mục "Hạn mức danh mục" của màn Tháng. Xóa danh mục thì xóa luôn hạn mức của nó.
- **Giới thiệu:** `OnboardingView` có ba bước, vuốt ngang để chuyển (`TabView` kiểu trang, không có nút Tiếp): cách gõ, nhắc và gợi ý (công tắc tùy chọn, chỉ xin quyền khi bật), rồi ngân sách tháng. Có ngân sách nghĩa là đã xong, nên bước ngân sách phải là bước cuối. Các ví dụ cách gõ ở bước đầu có test trong `OnboardingExamplesTests`; đổi ví dụ thì đổi test.
- **Màn Hôm nay:** hôm nay ở trên, các ngày trước nối tiếp bên dưới thành từng nhóm có tiêu đề (tên ngày và tổng; hôm nay cũng có tiêu đề này khi đã có khoản). Mỗi dòng hiện biểu tượng và tên danh mục ở dòng phụ (`ExpenseRow.category: CategoryInfo?`, tra bằng `CategoryCatalog`). Ô gõ tự viết hoa chữ đầu câu, chữ nói ra cũng viết hoa chữ đầu, cuộn để xem, không cần bấm. Rung nhẹ khi một ngày mới trượt vào màn hình, chỉ khi người dùng đang cuộn. Dữ liệu lấy từ truy vấn 35 ngày gần nhất. Thanh đáy có ô gõ, nút micro (mở ô gõ và nghe ngay qua `EntryRequest.startsListening`, ẩn khi thiếu khóa quyền) và nút chụp hóa đơn.
- **Hóa đơn:** `ReceiptParser` trả thêm danh sách món (`items`) và `isTotalConfident`; màn Hóa đơn cho chọn món của mình (tổng = các món đã chọn, chọn hết thì quay về tổng trên hóa đơn) và nhắc kiểm tra khi không chắc tổng.
- **Ghi trùng:** ô gõ hỏi lại khi khoản sắp ghi giống hệt (cùng tên, số tiền, ngày phát sinh) một khoản vừa ghi trong 5 phút (`DuplicateDetector`, logic thuần trong `Suggestions/`). Vuốt "Ghi lại" là chủ ý của người dùng nên không hỏi.
- **Bộ tách khoản chi:** hiểu `45k`, `45k5`, `45k rưỡi`, `1 triệu rưỡi`, `1 củ 2`, `chia 4`, `chia ba`, `chia tư`, `/4`. Cụm chỉ ngày (`hôm qua`, `tối qua`, `sáng nay`, `3 ngày trước`, `thứ 4`, `chủ nhật`, `ngày 5`, `ngày 5/10`) do `DateHint` nhận và bỏ khỏi tên khoản; kết quả nằm ở `ParsedExpense.date`, không bao giờ ở tương lai, nil nghĩa là ghi theo lúc này. `parse` luôn nhận `now` và `calendar`. Thêm cách gõ mới thì thêm test vào `AmountParsingTests`, `ExpenseParserTests` hoặc `DateHintTests`.
- **Sổ ứng:** `Loan` ("ứng cho Minh 200k", "cho Minh mượn") không phải chi tiêu và không bao giờ tính vào ngân sách. `ExpenseParser` nhận ra cách gõ này; khoản ứng hiện ở ô gõ (`EntryRow`) và màn Tháng, đánh dấu đã trả bằng `isRepaid`.
- **Chi tiết khoản chi:** `ExpenseDetailView` sửa tên, số tiền, ngày, danh mục, ngoài ngân sách; xem ảnh bằng `PhotoViewer`. `Expense` còn giữ vị trí (`latitude`, `longitude`, `placeName`), ảnh (`photo`, JPEG nén bằng `ImageCompressor`, lưu `externalStorage`), `originalAmount` và `splitCount` khi chia tiền; `authorName` để dành cho dùng chung và luôn nil.
- **Gợi ý và nhắc:** `TimeSuggester` và `PlaceSuggester` (logic thuần, `Suggestions/`) gợi ý khoản hay ghi theo giờ và vị trí, lấy vị trí qua `LocationProvider`. `NotificationManager` đặt nhắc 21:00 và nhắc khi rời quán quen (`PlaceMonitor`, `LeaveReminderPolicy`, `ReminderPlanner`).
- **Hỏi Xu:** `AskSection` ở đáy màn Tháng, trả lời bằng FoundationModels (`SpendingAnswering`) dựa trên `SpendingSnapshot` và `SpendingFacts` tính sẵn; số liệu do code tính, mô hình chỉ diễn đạt. Ẩn hoặc báo khi máy không hỗ trợ (`AskEngine.isAvailable`). Miễn phí.
- **App Intents:** `LogExpenseIntent` ("Ghi chi tiêu", không mở app) và `OpenEntryIntent`, đều qua `SaveGate.canSave`. `ShortcutsGuideView` trong Cài đặt hướng dẫn gắn vào Siri và Phím tắt. Widget đã bỏ, không làm lại khi chưa được yêu cầu.
- **Cài đặt và Pro:** `SettingsView` chia nhóm: Ngân sách (ngân sách tháng, `CategoryLimitsView`), Ghi chép (khoản định kỳ, `CategoriesView` kèm chọn biểu tượng), Nhắc và gợi ý, Hiển thị (giao diện sáng, tối, hệ thống; ngôn ngữ), Dữ liệu (xuất CSV), Trợ giúp và Pro. Thêm mục mới thì đặt vào đúng nhóm, đừng thêm nhóm lẻ.
- **Giao diện và ngôn ngữ:** `AppAppearance` áp bằng `preferredColorScheme` ở `XuApp`. `AppLanguage` ghi `AppleLanguages` trong `UserDefaults.standard` (không phải App Group) và bắt người dùng mở lại app, vì `String(localized:)`, thông báo và Siri đọc ngôn ngữ lúc khởi động (`AppSettings.needsRelaunchForLanguage`). Test dùng `AppSettings(defaults:standardDefaults:)` với suite riêng, không chạm `UserDefaults.standard`. `PaywallView` và `EntitlementStore` dùng StoreKit 2 (`Xu.storekit` để thử).
- **So sánh kỳ trước:** màn Tháng có mục "So với kỳ trước" (chọn tháng trước hoặc tuần trước). `PeriodComparison` (logic thuần, `Budget/`) so kỳ này tính tới hết hôm nay với đúng đoạn ngày đó của kỳ trước (không so tháng mới qua 10 ngày với cả tháng đã xong), chỉ tính khoản trong ngân sách, gồm cả danh mục chỉ có chi ở kỳ trước. Phần trăm làm tròn bằng số nguyên.
- **Đa tiền tệ:** `ForeignAmountParser` nhận `20 usd`, `$20`, `20$`, `usd 20`, `5 euro`, `€5`, `1000 yên`, `10k yên`, `20 đô la` (USD, EUR, JPY, KRW, CNY, GBP, THB, SGD, AUD); phải có tên hoặc ký hiệu tiền, không có thì vẫn là đồng. `ExpenseParser.rates` quy ra đồng (làm tròn 100đ) nên `ParsedExpense.amount` luôn là đồng; số gốc nằm ở `ParsedExpense.foreign` rồi `Expense.foreignCurrency` và `foreignMinor` (đơn vị nhỏ nhất, không dùng số thực; tỷ giá dùng `Decimal`). Sửa số tiền thì xóa số gốc. Không có mạng và không backend nên tỷ giá là giá trị gần đúng có sẵn (`Currency.defaultRate`), người dùng chỉnh ở `ExchangeRatesView`, lưu trong App Group (`ExchangeRates.load`); mọi chỗ gọi bộ tách để ghi phải truyền `ExchangeRates.load()`.
- **Xuất CSV:** `ExportDataRow` trong Tùy chỉnh chia sẻ mọi khoản chi (không giới hạn 35 ngày, miễn phí) qua `ShareLink`; tệp chỉ được tạo khi chia sẻ. Định dạng do `CSVExporter` (logic thuần, test `CSVExporterTests`) quyết định: cũ đến mới, CRLF, BOM UTF-8 cho Excel, số tiền là số đồng nguyên, ô chữ bắt đầu bằng `= + - @` thêm dấu nháy đơn để không thành công thức.
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
