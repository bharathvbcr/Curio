import SwiftUI

@main
struct CurioMacApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MacDeskView()
                .environment(environment)
                .curioTheme()
                .frame(minWidth: 1080, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 800)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            MacDeskMenuCommands()
        }

        Settings {
            MacAgentSettings()
                .curioTheme()
        }
    }
}
