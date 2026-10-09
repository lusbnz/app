import SwiftUI
import WidgetKit

@main
struct XuWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LockWidget()
    }
}
