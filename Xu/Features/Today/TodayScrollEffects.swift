import SwiftUI

/// Các ngày cũ hơn thì nhạt dần, và trượt nhẹ vào lần đầu hiện ra trên màn hình.
/// Tắt chuyển động khi người dùng bật "Giảm chuyển động", giữ nguyên độ tương phản khi bật "Tăng độ tương phản".
private struct DayDepthStyle: ViewModifier {
    /// 0 là ngày gần nhất trước hôm nay.
    let depth: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// Nhạt dần theo từng ngày, không xuống dưới 0,7 để chữ vẫn đọc được.
    private var dimmed: Double {
        contrast == .increased ? 1 : max(0.7, 1 - 0.05 * Double(depth))
    }

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? dimmed : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .onScrollVisibilityChange(threshold: 0.1) { visible in
                guard visible, !appeared else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func dayDepth(_ depth: Int) -> some View {
        modifier(DayDepthStyle(depth: depth))
    }
}

/// Vệt highlight dưới tiêu đề ngày: dài theo phần hạn mức ngày đã dùng, đỏ nhạt khi vượt.
struct DayLoadBar: View {
    let load: DayLoad
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.xuDivider.opacity(0.35))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(load.isOver ? Color.red.opacity(0.55) : Color.xuHighlight)
                        .frame(width: max(5, proxy.size.width * (shown ? load.fraction : 0)))
                }
        }
        .frame(height: 5)
        .onAppear { withAnimation(.spring(duration: 0.7)) { shown = true } }
        .accessibilityHidden(true)
    }
}

/// Thanh nhỏ ghim ở đầu màn hình khi số lớn đã cuộn khuất: ngày đang xem và số còn lại hôm nay.
struct CompactTodayBar: View {
    let dayTitle: String
    let amountText: String
    let fraction: Double
    let accessibilityText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.xuTextSecondary)
                .contentTransition(.opacity)
                .animation(.default, value: dayTitle)
            Spacer()
            HighlightedNumber(text: amountText, fraction: fraction, size: 26)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(Color.xuBackground.opacity(0.9))
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider().overlay(Color.xuDivider) }
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
