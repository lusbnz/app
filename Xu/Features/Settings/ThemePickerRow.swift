import SwiftUI

/// Chọn màu chủ đề (và biểu tượng app đi kèm). Chủ đề mặc định miễn phí, các chủ đề khác là của Pennyline Pro.
struct ThemePickerRow: View {
    @Environment(EntitlementStore.self) private var store
    @State private var themes = ThemeStore.shared
    /// Đổi biểu tượng app theo chủ đề; chỉ hiện khi dự án đã bật bộ biểu tượng thay thế.
    @AppStorage("themeSyncsIcon", store: AppGroup.defaults) private var syncsIcon = true

    /// Màu chủ đề khác mặc định cần Pro; nơi gọi tự hiện bảng mua, vì bảng mua của màn gốc không hiện được khi Tùy chỉnh đang mở.
    let needsPro: () -> Void

    private var supportsIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Màu chủ đề")
                if !store.isPro { ButterLabel(text: "PRO") }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(AppTheme.allCases) { theme in swatch(theme) }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            if supportsIcons {
                Toggle("Đổi cả biểu tượng app", isOn: $syncsIcon)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }

    private func swatch(_ theme: AppTheme) -> some View {
        let isSelected = themes.effective == theme
        let palette = theme.palette
        return Button { choose(theme) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(palette.background.color)
                    Circle().fill(palette.button.color).frame(width: 30, height: 30).offset(x: -6, y: -4)
                    Circle().fill(palette.highlight.color).frame(width: 18, height: 18).offset(x: 10, y: 10)
                }
                .frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(isSelected ? Color.xuTextPrimary : Color.xuDivider, lineWidth: isSelected ? 2.5 : 1))
                Text(theme.title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.xuTextPrimary : Color.xuTextSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ theme: AppTheme) {
        guard store.isPro || theme.isDefault else {
            needsPro()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) { themes.theme = theme }
        if syncsIcon, supportsIcons {
            Task { try? await UIApplication.shared.setAlternateIconName(theme.iconName) }
        }
    }
}

#Preview {
    Form { ThemePickerRow(needsPro: {}) }.xuPreview()
}
