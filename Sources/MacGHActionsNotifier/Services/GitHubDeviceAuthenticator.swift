import Foundation

struct DeviceFlowSession: Equatable {
    var deviceCode: String
    var userCode: String
    var verificationURI: URL
    var expiresIn: TimeInterval
    var interval: TimeInterval
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}

final class GitHubDeviceAuthenticator {
    private let clientID: String
    private let tokenStore: any KeychainStore
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(clientID: String, tokenStore: any KeychainStore, session: URLSession = .shared) {
        self.clientID = clientID
        self.tokenStore = tokenStore
        self.session = session
    }

    func requestDeviceCode(scopes: [String]) async throws -> DeviceFlowSession {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": clientID,
            "scope": scopes.joined(separator: " ")
        ])

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response)
        let decoded = try decoder.decode(DeviceCodeResponse.self, from: data)
        return DeviceFlowSession(
            deviceCode: decoded.deviceCode,
            userCode: decoded.userCode,
            verificationURI: decoded.verificationURI,
            expiresIn: decoded.expiresIn,
            interval: decoded.interval ?? 5
        )
    }

    func pollForToken(session deviceSession: DeviceFlowSession) async throws {
        let started = Date()
        var interval = max(5, deviceSession.interval)

        while Date().timeIntervalSince(started) < deviceSession.expiresIn {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            let response = try await requestToken(deviceCode: deviceSession.deviceCode)

            if let accessToken = response.accessToken, response.tokenType?.lowercased() == "bearer" {
                try tokenStore.saveToken(accessToken)
                return
            }

            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "expired_token":
                throw AppError.authentication("The GitHub device code expired. Start sign in again.")
            case "access_denied":
                throw AppError.authentication("GitHub sign in was cancelled.")
            default:
                throw AppError.authentication(response.errorDescription ?? "GitHub sign in failed.")
            }
        }

        throw AppError.authentication("The GitHub device code expired. Start sign in again.")
    }

    private func requestToken(deviceCode: String) async throws -> AccessTokenResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response)
        return try decoder.decode(AccessTokenResponse.self, from: data)
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AppError.network("GitHub authentication returned an invalid response.")
        }
    }

    private func formEncoded(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
