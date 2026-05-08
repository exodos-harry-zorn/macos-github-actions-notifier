import Foundation

protocol ConfigurationStore {
    func load() -> AppConfiguration
    func save(_ configuration: AppConfiguration)
}

final class UserDefaultsConfigurationStore: ConfigurationStore {
    private let key = "app.configuration.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? decoder.decode(AppConfiguration.self, from: data) else {
            return .default
        }
        return configuration.normalized()
    }

    func save(_ configuration: AppConfiguration) {
        guard let data = try? encoder.encode(configuration.sanitizedForPersistence()) else { return }
        defaults.set(data, forKey: key)
    }
}
