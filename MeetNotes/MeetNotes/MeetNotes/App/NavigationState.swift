import Observation

@Observable @MainActor final class NavigationState {
    @MainActor static let shared = NavigationState()
}
