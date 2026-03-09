import Observation
import Testing
@testable import MeetNotes

struct PermissionStatusTests {
    @Test func isGrantedReturnsTrueOnlyForAuthorized() {
        #expect(PermissionStatus.authorized.isGranted == true)
        #expect(PermissionStatus.notDetermined.isGranted == false)
        #expect(PermissionStatus.denied.isGranted == false)
        #expect(PermissionStatus.restricted.isGranted == false)
    }
}

@MainActor
struct MockPermissionServiceTests {
    @Test func mockConformsToProtocolAndTracksState() {
        let mock = MockPermissionService()
        #expect(mock.microphoneStatus == .notDetermined)
        #expect(mock.screenRecordingStatus == .notDetermined)
        #expect(mock.requestMicrophoneCalled == false)
        #expect(mock.requestScreenRecordingCalled == false)
        #expect(mock.refreshStatusCalled == false)
    }

    @Test func requestMicrophoneUpdatesMicrophoneStatus() async {
        let mock = MockPermissionService()
        await mock.requestMicrophone()
        #expect(mock.requestMicrophoneCalled == true)
        #expect(mock.microphoneStatus == .authorized)
    }

    @Test func refreshStatusCanBeCalledAndIsTrackable() {
        let mock = MockPermissionService()
        mock.refreshStatus()
        #expect(mock.refreshStatusCalled == true)
    }

    @Test func manualStatusChangeReflectsInIsGranted() {
        let mock = MockPermissionService()
        mock.microphoneStatus = .authorized
        #expect(mock.microphoneStatus.isGranted == true)

        mock.microphoneStatus = .denied
        #expect(mock.microphoneStatus.isGranted == false)
    }

    @Test func requestScreenRecordingTracksCall() {
        let mock = MockPermissionService()
        mock.requestScreenRecording()
        #expect(mock.requestScreenRecordingCalled == true)
    }

    @Test func openMicrophoneSettingsTracksCall() {
        let mock = MockPermissionService()
        mock.openMicrophoneSettings()
        #expect(mock.openMicrophoneSettingsCalled == true)
    }
}

@MainActor
struct PermissionServiceIntegrationTests {
    @Test func initializesAndSetsStatus() {
        let service = PermissionService()
        // After init, statuses should be queryable (values depend on system TCC state)
        let micStatus = service.microphoneStatus
        let screenStatus = service.screenRecordingStatus
        #expect(micStatus == .notDetermined || micStatus == .authorized || micStatus == .denied || micStatus == .restricted)
        #expect(screenStatus == .authorized || screenStatus == .denied)
    }

    @Test func startMonitoringIsIdempotent() {
        let service = PermissionService()
        // init() already calls startMonitoring(); calling again should be a no-op
        service.startMonitoring()
        service.stopMonitoring()
    }

    @Test func stopMonitoringIsIdempotent() {
        let service = PermissionService()
        service.stopMonitoring()
        service.stopMonitoring()
    }

    @Test func refreshStatusDoesNotCrash() {
        let service = PermissionService()
        service.refreshStatus()
        service.refreshStatus()
    }
}

@Observable @MainActor final class MockPermissionService: PermissionChecking {
    var microphoneStatus: PermissionStatus = .notDetermined
    var screenRecordingStatus: PermissionStatus = .notDetermined
    var requestMicrophoneCalled = false
    var requestScreenRecordingCalled = false
    var openMicrophoneSettingsCalled = false
    var refreshStatusCalled = false

    func requestMicrophone() async {
        requestMicrophoneCalled = true
        microphoneStatus = .authorized
    }

    func requestScreenRecording() {
        requestScreenRecordingCalled = true
    }

    func acknowledgeScreenRecordingGranted() {
        screenRecordingStatus = .authorized
    }

    func openMicrophoneSettings() {
        openMicrophoneSettingsCalled = true
    }

    func refreshStatus() {
        refreshStatusCalled = true
    }
}
