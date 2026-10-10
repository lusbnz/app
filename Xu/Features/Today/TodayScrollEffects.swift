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

/// Vệt highlight mảnh: một đường nền, một đoạn vàng bơ dài theo `fraction`, đỏ nhạt khi `isWarning`.
/// Dùng ở tiêu đề ngày (phần hạn mức ngày đã dùng) và ở mục tiêu tiết kiệm (phần đã để dành).
struct HighlightBar: View {
    let fraction: Double
    var isWarning = false
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.xuDivider.opacity(0.35))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(isWarning ? Color.red.opacity(0.55) : Color.xuHighlight)
                        .frame(width: max(5, proxy.size.width * (shown ? min(max(fraction, 0), 1) : 0)))
                }
        }
        .frame(height: 5)
        .onAppear { withAnimation(.spring(duration: 0.7)) { shown = true } }
        .accessibilityHidden(true)
    }
}

/// Vệt highlight dưới tiêu đề ngày: dài theo phần hạn mức ngày đã dùng, đỏ nhạt khi vượt.
struct DayLoadBar: View {
    let load: DayLoad

    var body: some View {
        HighlightBar(fraction: load.fraction, isWarning: load.isOver)
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
    let scrollToToday: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Chạm vào ngày và số để về hôm nay, thay cho một nút nổi che dòng ở góc.
            Button(action: scrollToToday) {
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
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Về hôm nay")
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
    /// Vị trí cuộn trong cả danh sách, 0 ở đầu và 1 ở cuối, để đặt nút kéo của dải ngày.
    private(set) var scrollFraction: CGFloat = 0
    /// Nút kéo của dải ngày hiện khi đang cuộn, rồi ẩn sau một lúc.
    private(set) var thumbVisible = false

    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var isHolding = false
    @ObservationIgnored private var headerTops: [Date: CGFloat] = [:]
    @ObservationIgnored private var edge: CGFloat = 116

    func setCollapse(_ value: CGFloat) {
        if value != collapse { collapse = value }
    }

    func setFraction(_ value: CGFloat) {
        if value != scrollFraction { scrollFraction = value }
    }

    /// Đang cuộn thì hiện nút kéo; dừng cuộn một lúc thì ẩn, trừ khi người dùng đang cầm nút.
    func setScrolling(_ scrolling: Bool) {
        if scrolling {
            hideTask?.cancel()
            if !thumbVisible { thumbVisible = true }
        } else if !isHolding {
            scheduleHide()
        }
    }

    func hold(_ holding: Bool) {
        isHolding = holding
        if holding {
            hideTask?.cancel()
            if !thumbVisible { thumbVisible = true }
        } else {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.thumbVisible = false
        }
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
    let scrollToToday: () -> Void

    var body: some View {
        let collapse = tracker.collapse
        CompactTodayBar(
            dayTitle: VietnameseDate.relativeDay(tracker.currentDay ?? now, now: now, calendar: calendar),
            amountText: amountText,
            fraction: fraction,
            accessibilityText: accessibilityText,
            openSearch: openSearch,
            openSettings: openSettings,
            scrollToToday: scrollToToday
        )
        .opacity(collapse)
        .offset(y: (1 - collapse) * -10)
        // Chỉ nhận chạm khi đã hiện rõ, để lúc còn ẩn không chặn các dòng ở sát mép trên.
        .allowsHitTesting(collapse >= 0.5)
        .accessibilityHidden(collapse < 0.5)
    }
}
