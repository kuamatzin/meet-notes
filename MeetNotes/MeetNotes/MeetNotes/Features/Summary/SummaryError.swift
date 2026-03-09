import Foundation

enum SummaryError: Error, Sendable {
    case ollamaNotReachable(endpoint: String)
    case invalidAPIKey
    case networkUnavailable
    case providerFailure(Error)
}
