# XuWidgets

Mã nguồn của target widget. Thư mục này chưa thuộc target nào cho tới khi bạn thêm
Widget Extension tên `XuWidgets` trong Xcode (xem hướng dẫn ở phần tóm tắt giai đoạn 5).

Target widget cần thêm các tệp dùng chung sau của app (Target Membership):

- `Xu/Parsing/`, `Xu/Budget/`, `Xu/Formatting/`, `Xu/Models/`
- `Xu/Suggestions/Suggestion.swift`, `Xu/Ask/SpendingSnapshot.swift`
- `Xu/App/AppGroup.swift`, `Xu/App/XuStore.swift`
- `Xu/Store/SaveQuota.swift`
- `Xu/Intents/LogQuickExpenseIntent.swift`
- `Xu/DesignSystem/HighlightedNumber.swift`
- `Xu/Assets.xcassets`, `Xu/Localizable.xcstrings`
