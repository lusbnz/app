import SwiftUI

/// Khối Hỏi Pennyline ở đáy màn hình Tháng: câu hỏi gần nhất, câu trả lời, và ô hỏi câu khác.
struct AskSection: View {
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @State private var text = ""
    @State private var isAsking = false

    let snapshot: SpendingSnapshot
    /// Tên hiện cho khóa danh mục, để câu hỏi mẫu nói đúng tên người dùng đang thấy.
    var categoryTitle: (String) -> String = { String(localized: SpendingCategory(key: $0).title) }
    /// Thay được cách trả lời khi xem trước hoặc test.
    var answerer: (any SpendingAnswering)?
    var isAvailable = AskEngine.isAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hỏi Pennyline")
                .font(.subheadline.weight(.semibold))
            if !settings.lastQuestion.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.lastQuestion)
                        .foregroundStyle(Color.xuTextSecondary)
                    if isAsking {
                        ProgressView()
                    } else if !settings.lastAnswer.isEmpty {
                        Text(settings.lastAnswer)
                            .font(.title3.weight(.medium))
                    }
                }
            }
            if isAvailable {
                samples
                HStack {
                    TextField("Hỏi Pennyline câu khác", text: $text)
                        .submitLabel(.send)
                        .onSubmit { ask(text) }
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 50)
                .background(Color.xuSurface, in: .capsule)
                .disabled(isAsking)
            } else {
                Text("Máy này chưa hỗ trợ Hỏi Pennyline")
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
        .task(id: appState.pendingQuestion) {
            // Câu hỏi vừa gõ ở ô gõ.
            if let question = appState.pendingQuestion {
                appState.pendingQuestion = nil
                ask(question)
            }
        }
    }

    /// Câu hỏi mẫu chọn theo số liệu tháng này; chạm là hỏi ngay.
    @ViewBuilder
    private var samples: some View {
        let questions = AskSuggestions.make(
            snapshot: snapshot, categoryTitle: { snapshot.categoryNames[$0] ?? categoryTitle($0) }
        )
        AskSampleChips(questions: questions, isDisabled: isAsking) { ask($0) }
    }

    private func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }
        settings.lastQuestion = question
        settings.lastAnswer = ""
        guard isAvailable else { return }
        text = ""
        isAsking = true
        Task {
            defer { isAsking = false }
            settings.lastAnswer = await AskRunner.answer(question, snapshot: snapshot, calendar: calendar, answerer: answerer) ?? ""
        }
    }
}

private struct PreviewAnswerer: SpendingAnswering {
    func answer(_ question: String, context: SpendingSnapshot) async throws -> String {
        "232k cho 8 lần, trung bình 29k mỗi lần."
    }
}

#Preview("Có mô hình") {
    AskSection(
        snapshot: SpendingSnapshot.make(records: [], monthlyBudget: 9_000_000, now: Date(), calendar: .current),
        answerer: PreviewAnswerer(), isAvailable: true
    )
    .padding(24)
    .xuScreen()
    .xuPreview()
}

#Preview("Máy chưa hỗ trợ") {
    AskSection(
        snapshot: SpendingSnapshot.make(records: [], monthlyBudget: 9_000_000, now: Date(), calendar: .current),
        isAvailable: false
    )
    .padding(24)
    .xuScreen()
    .xuPreview()
}
