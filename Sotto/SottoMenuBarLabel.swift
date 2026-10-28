import SwiftUI

struct SottoMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let observer: RecordingStateObserver

    var body: some View {
        MenuBarIcon(observer: observer)
            .onAppear {
                SottoWindowCoordinator.shared.registerOpener { id in
                    openWindow(id: id)
                }
            }
            // App-level deep-link routing: the menu-bar label is the one view
            // always instantiated, so it owns the `.navigateToDestination`
            // subscription. Routing here (not inside the on-demand Sotto window)
            // means Settings/History/etc. links resolve even when the window is
            // closed — previously a dropped no-op.
            .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
                guard let destination = notification.userInfo?["destination"] as? String else { return }
                SottoWindowCoordinator.shared.route(destination: destination)
            }
    }
}
