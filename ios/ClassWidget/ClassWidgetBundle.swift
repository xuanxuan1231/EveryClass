import SwiftUI
import WidgetKit

/// Widget Extension 的入口。放在 ClassWidget target 中。
@main
struct ClassWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            ClassWidgetLiveActivity()
        }
    }
}
