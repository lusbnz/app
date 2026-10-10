import Observation
import SwiftUI

/// Màu của một vai trò, bản sáng và bản tối, viết dạng 0xRRGGBB.
struct ThemeTone: Sendable {
    let light: UInt32
    let dark: UInt32

    var color: Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Bảng màu đầy đủ của một chủ đề. Màu danh mục (`xuCategory*`) giữ nguyên ở mọi chủ đề vì chúng mang nghĩa.
struct ThemePalette: Sendable {
    var background: ThemeTone
    var surface: ThemeTone
    var divider: ThemeTone
    var button: ThemeTone
    var onButton: ThemeTone
    var highlight: ThemeTone
    var toggle: ThemeTone
    var textPrimary: ThemeTone
    var textSecondary: ThemeTone
    var strongSurface: ThemeTone
    var onStrongSurface: ThemeTone
}

/// Chủ đề màu. Mặc định (tím nhạt) miễn phí; các chủ đề khác là của Pennyline Pro.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case lavender, mint, peach, sky, coffee, graphite

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .lavender: "Tím nhạt"
        case .mint: "Bạc hà"
        case .peach: "Hồng đào"
        case .sky: "Trời xanh"
        case .coffee: "Cà phê"
        case .graphite: "Than chì"
        }
    }

    /// Tên bộ biểu tượng app đi cùng chủ đề; nil là biểu tượng mặc định.
    var iconName: String? {
        switch self {
        case .lavender: nil
        case .mint: "AppIcon-Mint"
        case .peach: "AppIcon-Peach"
        case .sky: "AppIcon-Sky"
        case .coffee: "AppIcon-Coffee"
        case .graphite: "AppIcon-Graphite"
        }
    }

    var isDefault: Bool { self == .lavender }

    var palette: ThemePalette {
        switch self {
        case .lavender:
            ThemePalette(
                background: .init(light: 0xFAF8FD, dark: 0x17131F), surface: .init(light: 0xEFEAF8, dark: 0x241E33),
                divider: .init(light: 0xE6E0F2, dark: 0x322A45), button: .init(light: 0xCDBFF5, dark: 0xCDBFF5),
                onButton: .init(light: 0x2B2440, dark: 0x2B2440), highlight: .init(light: 0xFFE08A, dark: 0x8A6D1F),
                toggle: .init(light: 0x8E7FD6, dark: 0x9D8FE6), textPrimary: .init(light: 0x2B2440, dark: 0xEFEAFA),
                textSecondary: .init(light: 0x6B6480, dark: 0xA59DBC), strongSurface: .init(light: 0x2B2440, dark: 0xEFEAFA),
                onStrongSurface: .init(light: 0xFAF8FD, dark: 0x2B2440)
            )
        case .mint:
            ThemePalette(
                background: .init(light: 0xF6FBF8, dark: 0x111A16), surface: .init(light: 0xE6F3EC, dark: 0x1B2923),
                divider: .init(light: 0xDAEBE1, dark: 0x2A3B33), button: .init(light: 0xBFEBD2, dark: 0xBFEBD2),
                onButton: .init(light: 0x1F3A2E, dark: 0x1F3A2E), highlight: .init(light: 0xFFE08A, dark: 0x8A6D1F),
                toggle: .init(light: 0x3FA37A, dark: 0x5BC096), textPrimary: .init(light: 0x1F3A2E, dark: 0xE6F5EC),
                textSecondary: .init(light: 0x5C7A6B, dark: 0x9DB8AA), strongSurface: .init(light: 0x1F3A2E, dark: 0xE6F5EC),
                onStrongSurface: .init(light: 0xF6FBF8, dark: 0x1F3A2E)
            )
        case .peach:
            ThemePalette(
                background: .init(light: 0xFFF8F5, dark: 0x1F1514), surface: .init(light: 0xFBEAE3, dark: 0x2E1F1C),
                divider: .init(light: 0xF3DDD3, dark: 0x45302B), button: .init(light: 0xF9C9B6, dark: 0xF9C9B6),
                onButton: .init(light: 0x3B2420, dark: 0x3B2420), highlight: .init(light: 0xFFE08A, dark: 0x8A6D1F),
                toggle: .init(light: 0xE2765A, dark: 0xF09378), textPrimary: .init(light: 0x3B2420, dark: 0xF8E8E2),
                textSecondary: .init(light: 0x86655C, dark: 0xC2A39A), strongSurface: .init(light: 0x3B2420, dark: 0xF8E8E2),
                onStrongSurface: .init(light: 0xFFF8F5, dark: 0x3B2420)
            )
        case .sky:
            ThemePalette(
                background: .init(light: 0xF5F9FE, dark: 0x111722), surface: .init(light: 0xE6EFFB, dark: 0x1A2433),
                divider: .init(light: 0xD8E5F5, dark: 0x2A3850), button: .init(light: 0xBBD6F7, dark: 0xBBD6F7),
                onButton: .init(light: 0x1F2E4A, dark: 0x1F2E4A), highlight: .init(light: 0xFFE08A, dark: 0x8A6D1F),
                toggle: .init(light: 0x4C86D9, dark: 0x6FA0EA), textPrimary: .init(light: 0x1F2E4A, dark: 0xE3EDFB),
                textSecondary: .init(light: 0x5B6E8C, dark: 0x9DB0CE), strongSurface: .init(light: 0x1F2E4A, dark: 0xE3EDFB),
                onStrongSurface: .init(light: 0xF5F9FE, dark: 0x1F2E4A)
            )
        case .coffee:
            ThemePalette(
                background: .init(light: 0xFBF7F2, dark: 0x1A1511), surface: .init(light: 0xF1E8DC, dark: 0x2A2119),
                divider: .init(light: 0xE5D9C8, dark: 0x41342A), button: .init(light: 0xE3CBA8, dark: 0xE3CBA8),
                onButton: .init(light: 0x3A2A1E, dark: 0x3A2A1E), highlight: .init(light: 0xF5D58A, dark: 0x8A6D1F),
                toggle: .init(light: 0xA9744B, dark: 0xC79163), textPrimary: .init(light: 0x3A2A1E, dark: 0xF2E8DA),
                textSecondary: .init(light: 0x7A6655, dark: 0xB7A28E), strongSurface: .init(light: 0x3A2A1E, dark: 0xF2E8DA),
                onStrongSurface: .init(light: 0xFBF7F2, dark: 0x3A2A1E)
            )
        case .graphite:
            ThemePalette(
                background: .init(light: 0xF7F7F8, dark: 0x121214), surface: .init(light: 0xEBEBED, dark: 0x1E1E21),
                divider: .init(light: 0xDEDEE0, dark: 0x333337), button: .init(light: 0xD4D4D8, dark: 0xD4D4D8),
                onButton: .init(light: 0x1F1F24, dark: 0x1F1F24), highlight: .init(light: 0xFFE08A, dark: 0x8A6D1F),
                toggle: .init(light: 0x5B5B66, dark: 0x9A9AA6), textPrimary: .init(light: 0x1F1F24, dark: 0xEDEDF0),
                textSecondary: .init(light: 0x6B6B75, dark: 0xA3A3AD), strongSurface: .init(light: 0x1F1F24, dark: 0xEDEDF0),
                onStrongSurface: .init(light: 0xF7F7F8, dark: 0x1F1F24)
            )
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        )
    }
}

/// Chủ đề đang dùng. `@Observable` nên mọi View đọc `Color.xu...` trong `body` tự vẽ lại khi đổi chủ đề, không cần
/// bọc `@Environment`. Người dùng hết Pennyline Pro thì tự về chủ đề mặc định (không xóa lựa chọn, mua lại là có lại).
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    /// Chủ đề người dùng chọn.
    var theme: AppTheme {
        didSet { AppGroup.defaults.set(theme.rawValue, forKey: SettingsKey.appTheme) }
    }
    /// `EntitlementStore` cập nhật khi Pennyline Pro đổi.
    var proUnlocked: Bool

    init(defaults: UserDefaults = AppGroup.defaults) {
        theme = AppTheme(rawValue: defaults.string(forKey: SettingsKey.appTheme) ?? "") ?? .lavender
        proUnlocked = defaults.bool(forKey: "isPro")
    }

    /// Chủ đề thực sự được vẽ.
    var effective: AppTheme { proUnlocked ? theme : .lavender }
    var palette: ThemePalette { effective.palette }
}

extension Color {
    static var xuBackground: Color { ThemeStore.shared.palette.background.color }
    static var xuSurface: Color { ThemeStore.shared.palette.surface.color }
    static var xuDivider: Color { ThemeStore.shared.palette.divider.color }
    static var xuButton: Color { ThemeStore.shared.palette.button.color }
    static var xuOnButton: Color { ThemeStore.shared.palette.onButton.color }
    static var xuHighlight: Color { ThemeStore.shared.palette.highlight.color }
    static var xuToggle: Color { ThemeStore.shared.palette.toggle.color }
    static var xuTextPrimary: Color { ThemeStore.shared.palette.textPrimary.color }
    static var xuTextSecondary: Color { ThemeStore.shared.palette.textSecondary.color }
    static var xuStrongSurface: Color { ThemeStore.shared.palette.strongSurface.color }
    static var xuOnStrongSurface: Color { ThemeStore.shared.palette.onStrongSurface.color }
}
