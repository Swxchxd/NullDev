import SwiftUI

@main
struct NullDevApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup("NullDev") {
            ContentView().environment(store)
        }
        .defaultSize(width: 1180, height: 790)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Navigate") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { store.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
        Settings {
            SettingsView().environment(store).frame(width: 650, height: 680)
                .preferredColorScheme(store.appearance.scheme).tint(Theme.accent)
        }
    }
}
