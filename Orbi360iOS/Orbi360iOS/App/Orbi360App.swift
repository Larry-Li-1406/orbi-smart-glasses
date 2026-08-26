import SwiftUI

@main
struct Orbi360App: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(viewModel)
        }
    }
}
