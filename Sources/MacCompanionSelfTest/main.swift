import Foundation
import MacCompanionCore

let config = AppConfig.default.feiniu
let rule = FeiniuFirewallClient.makeAllowAllRule(ip: "1.2.3.4", priority: 22, config: config)

precondition(rule.ifname == "ALL")
precondition(rule.flowdir == 1)
precondition(rule.pro == 1)
precondition(rule.ports.type == 1)
precondition(rule.ports.ranges.range?.from == 1)
precondition(rule.ports.ranges.range?.to == 65535)
precondition(rule.ips.type == 0)
precondition(rule.ips.ip == "1.2.3.4")
precondition(rule.allow)
precondition(rule.enable)
precondition(rule.priority == 22)
precondition(FeiniuFirewallClient.isExistingAllowAllRule(rule, ip: "1.2.3.4", range: config.portRange))
precondition(!FeiniuFirewallClient.isExistingAllowAllRule(rule, ip: "1.2.3.5", range: config.portRange))

print("MacCompanionSelfTest passed")
