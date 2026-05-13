import Foundation

final class AppFileLogger {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    let logFileURL: URL
    let logDirectoryURL: URL

    private let queue = DispatchQueue(label: "MacCompanion.AppFileLogger")
    private let isoFormatter = ISO8601DateFormatter()
    private let maxFileSize = 5 * 1024 * 1024

    init(fileManager: FileManager = .default) {
        logDirectoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("MacCompanion", isDirectory: true)
        logFileURL = logDirectoryURL.appendingPathComponent("MacCompanion.log")

        try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    func debug(_ message: String, category: String = "app", details: [String: String] = [:]) {
        write(level: .debug, category: category, message: message, details: details)
    }

    func info(_ message: String, category: String = "app", details: [String: String] = [:]) {
        write(level: .info, category: category, message: message, details: details)
    }

    func warning(_ message: String, category: String = "app", details: [String: String] = [:]) {
        write(level: .warning, category: category, message: message, details: details)
    }

    func error(_ message: String, category: String = "app", details: [String: String] = [:]) {
        write(level: .error, category: category, message: message, details: details)
    }

    private func write(level: Level, category: String, message: String, details: [String: String]) {
        let timestamp = isoFormatter.string(from: Date())
        let detailText = details
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        let suffix = detailText.isEmpty ? "" : " \(detailText)"
        let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(sanitize(message))\(suffix)\n"

        queue.async { [logFileURL, maxFileSize] in
            let fileManager = FileManager.default
            if let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
               let size = attributes[.size] as? NSNumber,
               size.intValue > maxFileSize {
                let rotatedURL = logFileURL.deletingLastPathComponent().appendingPathComponent("MacCompanion.log.1")
                try? fileManager.removeItem(at: rotatedURL)
                try? fileManager.moveItem(at: logFileURL, to: rotatedURL)
                fileManager.createFile(atPath: logFileURL.path, contents: nil)
            }

            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                fileManager.createFile(atPath: logFileURL.path, contents: data)
            }
        }
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
