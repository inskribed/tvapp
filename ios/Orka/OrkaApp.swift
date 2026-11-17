import SwiftUI

@main
struct OrkaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(model.accent)
        }
    }
}
