import SwiftUI

extension SpendingCategory {
    var title: LocalizedStringResource {
        switch self {
        case .food: "ăn uống"
        case .transport: "đi lại"
        case .shopping: "mua sắm"
        case .bills: "hóa đơn"
        case .health: "sức khỏe"
        case .fun: "giải trí"
        case .other: "khác"
        }
    }

    var color: Color {
        switch self {
        case .food: .xuCategoryFood
        case .transport: .xuCategoryTransport
        case .shopping: .xuCategoryShopping
        case .bills, .health, .fun, .other: .xuCategoryOther
        }
    }
}

extension View {
    /// Nền và màu chữ chung của mọi màn hình.
    func xuScreen() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.xuBackground.ignoresSafeArea())
            .foregroundStyle(Color.xuTextPrimary)
    }

    /// Số tiền: chữ số đều nhau, VoiceOver đọc số đầy đủ.
    func money(_ amount: Int) -> some View {
        monospacedDigit().accessibilityLabel(MoneyFormatter.spoken(amount))
    }
}

/// Nút chính: nền tím nhạt, chữ màu chữ chính.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.xuOnButton)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.xuButton, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

/// Nút phụ: nền phụ.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.xuTextPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.xuSurface, in: .capsule)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Nhãn nhỏ nền vàng bơ: "ngoài ngân sách", "PRO".
struct ButterLabel: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.xuTextPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.xuHighlight, in: .rect(cornerRadius: 4))
    }
}

#Preview {
    VStack(spacing: 16) {
        Button("Bắt đầu") {}.buttonStyle(PrimaryButtonStyle())
        Button("Chụp lại") {}.buttonStyle(SecondaryButtonStyle())
        ButterLabel(text: "ngoài ngân sách")
    }
    .padding()
    .xuScreen()
}
