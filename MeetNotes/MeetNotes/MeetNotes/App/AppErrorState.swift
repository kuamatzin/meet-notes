import Observation

@Observable @MainActor final class AppErrorState {
    var current: AppError?

    func post(_ error: AppError) { current = error }
    func clear() { current = nil }
}
