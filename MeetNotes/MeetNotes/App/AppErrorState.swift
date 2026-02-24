import Observation

@Observable @MainActor final class AppErrorState {
    var current: AppError?
}
