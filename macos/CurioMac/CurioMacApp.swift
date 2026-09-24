import SwiftUI

@main
struct CurioMacApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MacDeskView()
                .environment(environment)
                .curioTheme()
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
