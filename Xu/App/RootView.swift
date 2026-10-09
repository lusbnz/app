import SwiftUI

/// Điều hướng gốc: lần đầu mở app, rồi Hôm nay và các sheet.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    var body: some View {
        @Bindable var appState = appState
        Group {
            if settings.monthlyBudget > 0 {
                NavigationStack {
                    TodayView(now: now)
                }
                .sheet(item: $appState.entry) { request in
                    EntryView(request: request, now: now)
                }
            } else {
                OnboardingView()
            }
        }
        .sensoryFeedback(.success, trigger: appState.saveCount)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
    }
}

#Preview("Hôm nay") {
    RootView().xuPreview()
}

#Preview("Lần đầu") {
    RootView().xuPreview(budget: 0)
}
