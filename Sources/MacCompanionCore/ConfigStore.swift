import Foundation

final class ConfigStore {
    private let fileManager = FileManager.default

    var configURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".mac-companion/config.json")
    }

    func load() throws -> AppConfig {
        guard fileManager.fileExists(atPath: configURL.path) else {
            try save(.default)
            return .default
        }

        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
    }
}
