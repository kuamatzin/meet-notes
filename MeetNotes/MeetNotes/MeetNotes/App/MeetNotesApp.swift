import SwiftUI

@main
struct MeetNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var recordingVM = RecordingViewModel()
    @State private var appErrorState = AppErrorState()
    @State private var navigationState = NavigationState.shared

    var body: some Scene {
        MenuBarExtra("meet-notes", systemImage: "mic") {
            MenuBarPopoverView()
                .environment(recordingVM)
                .environment(appErrorState)
                .environment(navigationState)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Meetings", id: "Meetings") {
            MainWindowView()
                .environment(recordingVM)
                .environment(appErrorState)
                .environment(navigationState)
        }
        .commands {
            CommandMenu("Recording") {
                Button("Start Recording") { }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
