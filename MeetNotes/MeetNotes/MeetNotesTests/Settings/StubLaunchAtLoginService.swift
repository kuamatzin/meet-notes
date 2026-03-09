import Foundation
@testable import MeetNotes

final class StubLaunchAtLoginService: LaunchAtLoginService, @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled = false
    private var _registerCalled = false
    private var _unregisterCalled = false
    private var _shouldThrowOnRegister = false
    private var _shouldThrowOnUnregister = false

    var shouldThrowOnRegister: Bool {
        get { lock.withLock { _shouldThrowOnRegister } }
        set { lock.withLock { _shouldThrowOnRegister = newValue } }
    }
    var shouldThrowOnUnregister: Bool {
        get { lock.withLock { _shouldThrowOnUnregister } }
        set { lock.withLock { _shouldThrowOnUnregister = newValue } }
    }

    var registerCalled: Bool { lock.withLock { _registerCalled } }
    var unregisterCalled: Bool { lock.withLock { _unregisterCalled } }

    func isEnabled() -> Bool {
        lock.withLock { _enabled }
    }

    func register() throws {
        let shouldThrow = lock.withLock {
            _registerCalled = true
            return _shouldThrowOnRegister
        }
        if shouldThrow {
            throw StubLaunchAtLoginError.registrationFailed
        }
        lock.withLock { _enabled = true }
    }

    func unregister() throws {
        let shouldThrow = lock.withLock {
            _unregisterCalled = true
            return _shouldThrowOnUnregister
        }
        if shouldThrow {
            throw StubLaunchAtLoginError.unregistrationFailed
        }
        lock.withLock { _enabled = false }
    }
}

enum StubLaunchAtLoginError: Error {
    case registrationFailed
    case unregistrationFailed
}
