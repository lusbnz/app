import SwiftUI

/// Dải ngày kéo ở mép phải, như app Ảnh: hiện một nút nhỏ khi cuộn, kéo nút để nhảy tới một ngày.
/// Chỉ nút này nhận chạm, nên vuốt xóa ở mép phải của các dòng không bị chặn.
struct DayScrubber: View {
    let tracker: TodayScrollTracker
    /// Hôm nay rồi các ngày có khoản chi, mới nhất trước (`DayIndex.days`).
    let days: [Date]
    let now: Date
    let calendar: Calendar
    let jump: (Date) -> Void

    @State private var dragFraction: Double?
    @State private var jumpedDay: Date?

    private let thumbHeight: CGFloat = 52
    private let thumbWidth: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let travel = max(1, proxy.size.height - thumbHeight)
            let fraction = dragFraction ?? Double(tracker.scrollFraction)
            ZStack(alignment: .topTrailing) {
                Color.clear.allowsHitTesting(false)
                thumb
                    .offset(y: travel * min(max(fraction, 0), 1))
                    .gesture(drag(travel: travel))
                if dragFraction != nil, let jumpedDay {
                    Text(VietnameseDate.scrubLabel(jumpedDay, now: now, calendar: calendar))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.regularMaterial, in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.xuDivider))
                        .offset(x: -(thumbWidth + 6), y: travel * min(max(fraction, 0), 1) + (thumbHeight - 36) / 2)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
            .coordinateSpace(.named("scrubber"))
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: visible)
        .allowsHitTesting(visible)
        .sensoryFeedback(.selection, trigger: jumpedDay)
    }

    /// Ít ngày quá thì không cần dải kéo.
    private var visible: Bool {
        days.count > 5 && (tracker.thumbVisible || dragFraction != nil)
    }

    private var thumb: some View {
        Capsule()
            .fill(dragFraction == nil ? Color.xuTextSecondary.opacity(0.55) : Color.xuTextPrimary)
            .frame(width: dragFraction == nil ? 5 : 8, height: 38)
            .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
            .padding(.trailing, 5)
            .frame(width: thumbWidth, height: thumbHeight, alignment: .trailing)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("scrubber"))
            .onChanged { value in
                if dragFraction == nil { tracker.hold(true) }
                let fraction = min(max(Double((value.location.y - thumbHeight / 2) / travel), 0), 1)
                dragFraction = fraction
                guard let day = DayIndex.day(atFraction: fraction, in: days), day != jumpedDay else { return }
                jumpedDay = day
                jump(day)
            }
            .onEnded { _ in
                dragFraction = nil
                jumpedDay = nil
                tracker.hold(false)
            }
    }
}
