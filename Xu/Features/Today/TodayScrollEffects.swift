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
    let openSearch: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.xuTextSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.default, value: dayTitle)
                Spacer(minLength: 8)
                HighlightedNumber(text: amountText, fraction: fraction, size: 26)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            // Cuộn xa rồi vẫn tìm và mở Tùy chỉnh được, không phải cuộn ngược lên đầu.
            Button(action: openSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel("Tìm khoản chi")
            Button(action: openSettings) {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tùy chỉnh")
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .padding(.vertical, 2)
        .background {
            Rectangle()
                .fill(Color.xuBackground.opacity(0.9))
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider().overlay(Color.xuDivider) }
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Vị trí cuộn của màn Hôm nay. Chỉ `collapse` và `currentDay` được quan sát; vị trí các tiêu đề đổi từng khung hình
/// nên giữ ngoài cơ chế quan sát, tránh dựng lại giao diện mỗi lần cuộn.
@MainActor @Observable
final class TodayScrollTracker {
    /// 0 là số lớn còn nguyên, 1 là đã cuộn khuất hẳn và thanh nhỏ hiện ra.
    private(set) var collapse: CGFloat = 0
    /// Ngày đang nằm dưới thanh nhỏ; nil là hôm nay.
    private(set) var currentDay: Date?

    @ObservationIgnored private var headerTops: [Date: CGFloat] = [:]
    @ObservationIgnored private var edge: CGFloat = 116

    func setCollapse(_ value: CGFloat) {
        if value != collapse { collapse = value }
    }

    func setTopInset(_ inset: CGFloat) {
        edge = inset + 56
        refresh()
    }

    func headerMoved(day: Date, minY: CGFloat) {
        headerTops[day] = minY
        refresh()
    }

    private func refresh() {
        let day = Self.currentDay(headerTops: headerTops, edge: edge)
        if day != currentDay { currentDay = day }
    }

    /// Tiêu đề cuối cùng đã cuộn qua mép trên (lệch khỏi `edge` ít nhất); nil khi chưa tiêu đề nào qua, tức vẫn ở hôm nay.
    nonisolated static func currentDay(headerTops: [Date: CGFloat], edge: CGFloat) -> Date? {
        headerTops.filter { $0.value <= edge }.max { $0.value < $1.value }?.key
    }
}

/// Chỗ duy nhất đọc `TodayScrollTracker`, nên chỉ phần này được dựng lại khi cuộn.
struct ScrollingBarHost: View {
    let tracker: TodayScrollTracker
    let now: Date
    let calendar: Calendar
    let amountText: String
    let fraction: Double
    let accessibilityText: String
    let openSearch: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let collapse = tracker.collapse
        CompactTodayBar(
            dayTitle: VietnameseDate.relativeDay(tracker.currentDay ?? now, now: now, calendar: calendar),
            amountText: amountText,
            fraction: fraction,
            accessibilityText: accessibilityText,
            openSearch: openSearch,
            openSettings: openSettings
        )
        .opacity(collapse)
        .offset(y: (1 - collapse) * -10)
        // Chỉ nhận chạm khi đã hiện rõ, để lúc còn ẩn không chặn các dòng ở sát mép trên.
        .allowsHitTesting(collapse >= 0.5)
        .accessibilityHidden(collapse < 0.5)
    }
}
