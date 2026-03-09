import Foundation
import ServiceManagement

protocol LaunchAtLoginService: Sendable {
    func isEnabled() -> Bool
    func register() throws
    func unregister() throws
}

struct SMAppLaunchAtLoginService: LaunchAtLoginService {
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
