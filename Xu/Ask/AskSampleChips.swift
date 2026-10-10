import SwiftUI

/// Hàng câu hỏi mẫu cuộn ngang; chạm một câu là hỏi ngay.
struct AskSampleChips: View {
    let questions: [String]
    var isDisabled = false
    let action: (String) -> Void

    var body: some View {
        if !questions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(questions, id: \.self) { question in
                        Button { action(question) } label: {
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(Color.xuTextPrimary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(Color.xuSurface, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}
