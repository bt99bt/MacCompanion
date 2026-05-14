import Foundation

struct WiFiCodeServerDeployResult: Sendable {
    var architecture: String
    var imageFileName: String
    var output: String
}

final class WiFiCodeServerDeployClient: @unchecked Sendable {
    private let config: WiFiCodeServerDeployConfig
    private let password: String

    init(config: WiFiCodeServerDeployConfig, password: String) {
        self.config = config
        self.password = password
    }

    func deploy() async throws -> WiFiCodeServerDeployResult {
        try validate()
        return try await withTemporaryAskpass { askpassURL in
            let archOutput = try await runSSH(
                command: "uname -m",
                askpassURL: askpassURL,
                sudoPassword: nil
            )
            let architecture = archOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let homeOutput = try await runSSH(
                command: "printf %s \"$HOME\"",
                askpassURL: askpassURL,
                sudoPassword: nil
            )
            let remoteHome = homeOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageFileName = imageFileName(for: architecture)
            let imageURL = try resourceURL(
                fileName: imageFileName,
                subdirectory: "WifiCodeServerImages"
            )
            let scriptURL = try resourceURL(
                fileName: "deploy_wifi_code_server_remote.sh",
                subdirectory: "WifiCodeServerDeploy"
            )

            let workDirectory = resolvedRemoteWorkDirectory(home: remoteHome)
            _ = try await runSSH(
                command: "mkdir -p \(shellQuote(workDirectory))",
                askpassURL: askpassURL,
                sudoPassword: nil
            )
            try await runSCP(
                localURL: imageURL,
                remotePath: "\(workDirectory)/\(imageFileName)",
                askpassURL: askpassURL
            )
            try await runSCP(
                localURL: scriptURL,
                remotePath: "\(workDirectory)/deploy_wifi_code_server_remote.sh",
                askpassURL: askpassURL
            )

            let sudoCommand = [
                "sudo -S env",
                "BASE_DOMAIN=\(shellQuote(config.baseDomain))",
                "CONTAINER_NAME=\(shellQuote(config.containerName))",
                "IMAGE_NAME=\(shellQuote(config.imageName))",
                "HTTP_PORT=\(config.httpPort)",
                "DNS_PORT=\(config.dnsPort)",
                "ALLOW_DOCKER_INSTALL=\(config.allowDockerInstall ? "1" : "0")",
                "STOP_KNOWN_CONFLICTS=\(config.stopConflictingKnownContainers ? "1" : "0")",
                "IMAGE_TAR=\(shellQuote(imageFileName))",
                "./deploy_wifi_code_server_remote.sh"
            ].joined(separator: " ")
            let remoteCommand = [
                "cd \(shellQuote(workDirectory))",
                "chmod +x deploy_wifi_code_server_remote.sh",
                sudoCommand
            ].joined(separator: " && ")

            let output = try await runSSH(
                command: remoteCommand,
                askpassURL: askpassURL,
                sudoPassword: password
            )
            return WiFiCodeServerDeployResult(
                architecture: architecture,
                imageFileName: imageFileName,
                output: output
            )
        }
    }

    private func validate() throws {
        guard !config.sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WiFiCodeServerDeployError.invalidConfig("服务器地址为空")
        }
        guard !config.sshUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WiFiCodeServerDeployError.invalidConfig("SSH 用户名为空")
        }
        guard !password.isEmpty else {
            throw WiFiCodeServerDeployError.invalidConfig("SSH/sudo 密码为空")
        }
        guard config.sshPort > 0, config.sshPort <= 65535 else {
            throw WiFiCodeServerDeployError.invalidConfig("SSH 端口无效")
        }
        guard !config.remoteWorkDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WiFiCodeServerDeployError.invalidConfig("远端工作目录为空")
        }
        guard !config.baseDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WiFiCodeServerDeployError.invalidConfig("基础域名为空")
        }
    }

    private func imageFileName(for architecture: String) -> String {
        let normalized = architecture.lowercased()
        if normalized.contains("aarch64") || normalized.contains("arm64") {
            return "wifi-code-server-arm64.tar"
        }
        return "wifi-code-server-amd64.tar"
    }

    private func resolvedRemoteWorkDirectory(home: String) -> String {
        let trimmed = config.remoteWorkDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return home
        }
        if trimmed.hasPrefix("~/") {
            return URL(fileURLWithPath: home).appendingPathComponent(String(trimmed.dropFirst(2))).path
        }
        return trimmed
    }

    private func resourceURL(fileName: String, subdirectory: String) throws -> URL {
        if let bundled = Bundle.main.url(
            forResource: (fileName as NSString).deletingPathExtension,
            withExtension: (fileName as NSString).pathExtension,
            subdirectory: subdirectory
        ) {
            return bundled
        }

        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("server")
            .appendingPathComponent(subdirectory == "WifiCodeServerImages" ? "images" : "deploy")
            .appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }

        throw WiFiCodeServerDeployError.missingResource(fileName)
    }

    private func withTemporaryAskpass<T>(_ operation: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCompanion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("ssh-askpass.sh")
        let content = "#!/bin/sh\nprintf '%s\\n' \(shellQuote(password))\n"
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return try await operation(script)
    }

    private func runSSH(command: String, askpassURL: URL, sudoPassword: String?) async throws -> String {
        var arguments = sshBaseArguments(askpassURL: askpassURL)
        arguments.append("\(config.sshUsername)@\(config.sshHost)")
        arguments.append(command)
        return try await runProcess(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            askpassURL: askpassURL,
            stdin: sudoPassword.map { "\($0)\n" }
        )
    }

    private func runSCP(localURL: URL, remotePath: String, askpassURL: URL) async throws {
        var arguments = scpBaseArguments(askpassURL: askpassURL)
        arguments.append(localURL.path)
        arguments.append("\(config.sshUsername)@\(config.sshHost):\(remotePath)")
        _ = try await runProcess(
            executable: "/usr/bin/scp",
            arguments: arguments,
            askpassURL: askpassURL,
            stdin: nil
        )
    }

    private func sshBaseArguments(askpassURL: URL) -> [String] {
        [
            "-p", "\(config.sshPort)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(knownHostsPath)",
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password,keyboard-interactive,publickey",
            "-o", "KbdInteractiveAuthentication=yes",
            "-o", "PubkeyAuthentication=yes"
        ]
    }

    private func scpBaseArguments(askpassURL: URL) -> [String] {
        [
            "-P", "\(config.sshPort)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(knownHostsPath)",
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password,keyboard-interactive,publickey",
            "-o", "KbdInteractiveAuthentication=yes",
            "-o", "PubkeyAuthentication=yes"
        ]
    }

    private var knownHostsPath: String {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mac-companion", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("known_hosts").path
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        askpassURL: URL,
        stdin: String?
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["SSH_ASKPASS"] = askpassURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = "MacCompanion:0"
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            if let stdin {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                try process.run()
                if let data = stdin.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
                try? inputPipe.fileHandleForWriting.close()
            } else {
                try process.run()
            }

            process.waitUntilExit()
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let combined = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
            guard process.terminationStatus == 0 else {
                throw WiFiCodeServerDeployError.processFailed(combined)
            }
            return combined
        }.value
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

enum WiFiCodeServerDeployError: LocalizedError {
    case invalidConfig(String)
    case missingResource(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let message):
            return message
        case .missingResource(let name):
            return "缺少部署资源：\(name)"
        case .processFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "远端部署命令执行失败" : trimmed
        }
    }
}
