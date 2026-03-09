import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates\u{2026}", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
            .accessibilityLabel("Check for updates")
    }
}
