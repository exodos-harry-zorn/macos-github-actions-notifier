import Foundation

enum AppError: LocalizedError, Equatable {
    case authentication(String)
    case api(String)
    case keychain(String)
    case network(String)
    case rateLimited(String)

    var errorDescription: String? {
        switch self {
        case .authentication(let message),
             .api(let message),
             .keychain(let message),
             .network(let message),
             .rateLimited(let message):
            message
        }
    }
}

enum ErrorPresenter {
    static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
