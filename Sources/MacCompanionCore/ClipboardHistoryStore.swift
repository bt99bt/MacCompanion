import Foundation

final class ClipboardHistoryStore {
    private let fileManager = FileManager.default

    var historyURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".mac-companion/clipboard-history.json")
    }

    func load() throws -> [ClipboardHistoryItem] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }
        let data = try Data(contentsOf: historyURL)
        return try JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
    }

    func save(_ items: [ClipboardHistoryItem]) throws {
        let directory = historyURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: historyURL, options: [.atomic])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }
        try fileManager.removeItem(at: historyURL)
    }
}
