import WidgetKit
import SwiftUI

/// Widget bundle for Curio's Live Activity extension. Curio ships exactly one Live Activity (the
/// unified background-activity indicator), so this bundle contains just `CurioActivityLiveActivity`.
@main
struct CurioActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurioActivityLiveActivity()
    }
}
