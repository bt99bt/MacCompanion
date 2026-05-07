import AppKit
import Foundation
import MacCompanionCore

@main
struct SmokeTest {
    @MainActor
    static func main() async {
        do {
            let client = FeiniuBrowserFirewallClient(config: AppConfig.default.feiniu)
            let summary = try await client.fetchFirewallSummary()
            print("Feiniu smoke test passed: profile=\(summary.profile), rules=\(summary.ruleCount), enabled=\(summary.enabled)")
        } catch {
            let nsError = error as NSError
            let userInfo = nsError.userInfo
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "; ")
            print("Feiniu smoke test failed: \(error.localizedDescription)")
            print("domain=\(nsError.domain) code=\(nsError.code)")
            if !userInfo.isEmpty {
                print("userInfo=\(userInfo)")
            }
            Foundation.exit(1)
        }
    }
}
