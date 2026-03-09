import Sparkle
import SwiftUI

@main
struct MeetNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var permissionService: PermissionService
    @State private var onboardingVM: OnboardingViewModel
    @State private var recordingVM: RecordingViewModel
    @State private var settingsVM: SettingsViewModel
    @State private var meetingListVM: MeetingListViewModel
    @State private var meetingDetailVM: MeetingDetailViewModel
    @State private var appErrorState = AppErrorState()
    @State private var navigationState = NavigationState.shared

    init() {
        let ps = PermissionService()
        let errorState = AppErrorState()
        let db = AppDatabase.shared
        let summaryService = SummaryService(database: db, appErrorState: errorState)
        let transcriptionService = TranscriptionService(database: db, summaryService: summaryService)
        let modelDownloadManager = ModelDownloadManager(database: db)
        let recService = RecordingService(database: db, transcriptionService: transcriptionService)
        let recVM = RecordingViewModel(
            permissionService: ps,
            recordingService: recService,
            appErrorState: errorState
        )
        let launchAtLoginService = SMAppLaunchAtLoginService()
        let settingsVM = SettingsViewModel(
            database: db,
            modelDownloadManager: modelDownloadManager,
            transcriptionService: transcriptionService,
            launchAtLoginService: launchAtLoginService,
            appErrorState: errorState
        )

        let meetingListVM = MeetingListViewModel(database: db, appErrorState: errorState)
        let meetingDetailVM = MeetingDetailViewModel(database: db, appErrorState: errorState, summaryService: summaryService)

        _permissionService = State(initialValue: ps)
        _onboardingVM = State(initialValue: OnboardingViewModel(permissionService: ps))
        _appErrorState = State(initialValue: errorState)
        _recordingVM = State(initialValue: recVM)
        _settingsVM = State(initialValue: settingsVM)
        _meetingListVM = State(initialValue: meetingListVM)
        _meetingDetailVM = State(initialValue: meetingDetailVM)

        appDelegate.recordingService = recService

        Task {
            await transcriptionService.setStateHandler { [weak recVM] state in
                recVM?.state = state
            }
            await transcriptionService.loadInitialModel()
            await transcriptionService.checkForStaleMeetings()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(permissionService)
                .environment(recordingVM)
                .environment(appErrorState)
                .environment(navigationState)
        } label: {
            MenuBarLabel(state: recordingVM.state)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Meetings", id: "Meetings") {
            MainWindowView()
                .environment(permissionService)
                .environment(recordingVM)
                .environment(meetingListVM)
                .environment(meetingDetailVM)
                .environment(appErrorState)
                .environment(navigationState)
                .sheet(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if !$0 { hasCompletedOnboarding = true } }
                )) {
                    OnboardingWizardView()
                        .interactiveDismissDisabled(true)
                        .environment(onboardingVM)
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
            CommandMenu("Recording") {
                Button(recordingVM.state.isRecording ? "Stop Recording" : "Start Recording") {
                    Task {
                        if recordingVM.state.isRecording {
                            await recordingVM.stopRecording()
                        } else {
                            await recordingVM.startRecording()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!recordingVM.state.isIdle && !recordingVM.state.isRecording)
            }
        }

        Settings {
            SettingsView(updater: appDelegate.updaterController.updater)
                .environment(settingsVM)
                .environment(appErrorState)
        }
    }
}

private struct MenuBarLabel: View {
    let state: RecordingState

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "mic")
        case .recording:
            WaveformView()
        case .processing:
            Image(systemName: "mic")
                .overlay(ProgressView().scaleEffect(0.5))
        case .error:
            Image(systemName: "mic.slash")
        }
    }
}
