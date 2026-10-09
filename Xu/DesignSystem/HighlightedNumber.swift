import SwiftUI

/// Con số lớn với một vệt vàng bơ phía sau, rộng theo tỉ lệ ngân sách còn lại.
struct HighlightedNumber: View {
    let text: String
    /// 0 đến 1. Bằng 0 thì vệt biến mất.
    let fraction: Double
    var size: CGFloat = 76

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        Text(text)
            .font(.system(size: size * min(scale, 1.4), weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            .padding(.horizontal, size * 0.08)
            .background {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: size * 0.06)
                        .fill(Color.xuHighlight)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1), height: proxy.size.height * 0.42)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .offset(y: -proxy.size.height * 0.1)
                }
            }
            .padding(.leading, -size * 0.08)
            .animation(.spring(duration: 0.6), value: fraction)
            .animation(.default, value: text)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        HighlightedNumber(text: "194k", fraction: 0.65)
        HighlightedNumber(text: "59k", fraction: 0.2)
        HighlightedNumber(text: "-56k", fraction: 0)
        HighlightedNumber(text: "7,1tr", fraction: 0.79, size: 44)
    }
    .padding()
    .xuScreen()
}
