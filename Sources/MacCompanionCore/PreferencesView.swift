import SwiftUI

public struct PreferencesView: View {
    @ObservedObject public var model: CompanionModel
    private let openEmbeddedFeiniuWeb: () -> Void
    @State private var selectedModule: Module = .feiniu

    public init(model: CompanionModel, openEmbeddedFeiniuWeb: @escaping () -> Void = {}) {
        self.model = model
        self.openEmbeddedFeiniuWeb = openEmbeddedFeiniuWeb
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            workspace
        }
        .frame(minWidth: 1080, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.isFeiniuWebLoginPresented) {
            feiniuLoginSheet
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Mac 伴侣")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Text("个人工具工作台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            ForEach(Module.allCases, id: \.self) { module in
                moduleButton(module)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("当前状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.isWorking ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(model.isWorking ? "处理中" : "空闲")
                        .font(.callout)
                        .fontWeight(.medium)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(18)
        .frame(width: 232)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func moduleButton(_ module: Module) -> some View {
        Button {
            selectedModule = module
        } label: {
            HStack(spacing: 11) {
                Image(systemName: module.icon)
                    .frame(width: 20)
                    .foregroundStyle(selectedModule == module ? Color.accentColor : Color.secondary)
                Text(module.title)
                    .fontWeight(selectedModule == module ? .semibold : .regular)
                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background {
                if selectedModule == module {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .glassEffect(.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedModule {
                    case .feiniu:
                        feiniuWorkspace
                    case .network:
                        networkWorkspace
                    case .clipboard:
                        clipboardWorkspace
                    case .automation:
                        placeholderWorkspace(
                            title: "自动化",
                            icon: "bolt",
                            detail: "这里会放常用脚本、定时检查、一键修复和可复用任务。"
                        )
                    case .settings:
                        settingsWorkspace
                    }
                }
                .padding(24)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedModule.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(model.status(for: selectedModule.logScope))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var feiniuWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            feiniuOverview
            feiniuFlow
            feiniuActions

            HStack(alignment: .top, spacing: 18) {
                connectionPanel
                whitelistPanel
            }

            activityLogPanel
        }
    }

    private var feiniuOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            statusTile(
                title: "网页登录态",
                value: model.loginState,
                icon: "person.crop.circle.badge.checkmark",
                tone: model.hasFeiniuSession ? .green : .orange
            )
            statusTile(
                title: "防火墙连接",
                value: model.firewallState,
                icon: "shield.lefthalf.filled",
                tone: model.firewallState.hasPrefix("已连接") ? .green : .gray
            )
            statusTile(
                title: "公网 IP",
                value: model.lastPublicIP,
                icon: "network",
                tone: model.lastPublicIP == "未知" ? .gray : .blue
            )
            statusTile(
                title: "飞牛地址",
                value: model.config.feiniu.webURL,
                icon: "server.rack",
                tone: .blue
            )
        }
    }

    private var feiniuFlow: some View {
        panel("执行流程", systemImage: "list.bullet.rectangle") {
            HStack(alignment: .top, spacing: 14) {
                flowStep(number: "1", title: "网页登录", detail: "打开内置网页，已有登录态会自动识别。", state: model.hasFeiniuSession ? .done : .current)
                flowStep(number: "2", title: "验证连接", detail: "读取飞牛防火墙配置。", state: model.firewallState.hasPrefix("已连接") ? .done : .pending)
                flowStep(number: "3", title: "添加白名单", detail: "把当前公网 IP 加到全端口允许规则。", state: model.lastPublicIP == "未知" ? .pending : .done)
            }
        }
    }

    private var feiniuActions: some View {
        panel("主要操作", systemImage: "play.circle") {
            HStack(spacing: 12) {
                Button {
                    openEmbeddedFeiniuWeb()
                } label: {
                    Label("打开飞牛面板", systemImage: "macwindow")
                        .frame(minWidth: 118)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.verifyFeiniuFirewallConnection() }
                } label: {
                    Label("验证连接", systemImage: "checkmark.seal")
                        .frame(minWidth: 104)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await model.refreshPublicIP() }
                } label: {
                    Label("刷新公网 IP", systemImage: "arrow.triangle.2.circlepath")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await model.addCurrentIPToFeiniuFirewall() }
                } label: {
                    Label("添加当前 IP", systemImage: "plus.circle")
                        .frame(minWidth: 116)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.return, modifiers: [.command])

                Button {
                    model.openFeiniuWeb()
                } label: {
                    Label("浏览器打开", systemImage: "safari")
                        .frame(minWidth: 104)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var connectionPanel: some View {
        panel("飞牛连接配置", systemImage: "slider.horizontal.3") {
            VStack(spacing: 10) {
                labeledField("Web 界面 URL", text: $model.config.feiniu.webURL)
                labeledField("WebSocket URL", text: $model.config.feiniu.websocketURL)
                labeledField("Origin", text: $model.config.feiniu.origin)
                labeledField("Token Cookie 名", text: $model.config.feiniu.tokenCookieName)
                labeledField("语言 Cookie", text: $model.config.feiniu.language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var whitelistPanel: some View {
        panel("白名单规则", systemImage: "lock.open") {
            VStack(spacing: 10) {
                labeledField("备注", text: $model.config.feiniu.memo)
                HStack(spacing: 10) {
                    Text("端口范围")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    TextField("起始", value: $model.config.feiniu.portRange.from, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                    Text("到")
                        .foregroundStyle(.secondary)
                    TextField("结束", value: $model.config.feiniu.portRange.to, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                    Spacer()
                }
                Button {
                    model.save()
                } label: {
                    Label("保存配置", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var clipboardWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            clipboardOverview
            clipboardActions

            HStack(alignment: .top, spacing: 18) {
                clipboardTriggerPanel
                clipboardStoragePanel
            }

            clipboardRecentPanel
            activityLogPanel
        }
    }

    private var clipboardOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            statusTile(
                title: "历史剪切板",
                value: model.config.clipboardHistory.isEnabled ? model.clipboardState : "已关闭",
                icon: "clipboard",
                tone: model.config.clipboardHistory.isEnabled ? .green : .gray
            )
            statusTile(
                title: "触发方式",
                value: model.clipboardTriggerSummary(),
                icon: "cursorarrow.click",
                tone: .blue
            )
            statusTile(
                title: "历史数量",
                value: "\(model.clipboardHistory.count) / \(model.config.clipboardHistory.maxItems)",
                icon: "clock.arrow.circlepath",
                tone: .blue
            )
            statusTile(
                title: "重启保留",
                value: model.config.clipboardHistory.persistHistory ? "开启" : "关闭",
                icon: "externaldrive",
                tone: model.config.clipboardHistory.persistHistory ? .green : .gray
            )
        }
    }

    private var clipboardActions: some View {
        panel("剪切板操作", systemImage: "clipboard") {
            HStack(spacing: 12) {
                Toggle(
                    "启用历史剪切板",
                    isOn: Binding(
                        get: { model.config.clipboardHistory.isEnabled },
                        set: { model.setClipboardHistoryEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Spacer()

                Button {
                    model.clearClipboardHistory()
                } label: {
                    Label("清空历史", systemImage: "trash")
                        .frame(minWidth: 104)
                }
                .buttonStyle(.bordered)

                Button {
                    model.save()
                } label: {
                    Label("保存配置", systemImage: "square.and.arrow.down")
                        .frame(minWidth: 112)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var clipboardTriggerPanel: some View {
        panel("呼出方式", systemImage: "cursorarrow.rays") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("触发方式", selection: $model.config.clipboardHistory.trigger.mode) {
                    ForEach(ClipboardTriggerMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("鼠标中键呼出时吞掉原事件", isOn: $model.config.clipboardHistory.trigger.swallowMiddleMouseClick)
                    .toggleStyle(.switch)
                    .disabled(model.config.clipboardHistory.trigger.mode != .middleMouse)

                labeledField("键盘快捷键", text: $model.config.clipboardHistory.trigger.keyboardShortcut)
                    .disabled(model.config.clipboardHistory.trigger.mode != .keyboard)

                Text("键盘格式示例：cmd+option+v、control+option+space。鼠标中键全局监听需要在系统设置里给 Mac 伴侣开启输入监控权限；吞掉中键事件可能还需要辅助功能权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.openAccessibilitySettings()
                } label: {
                    Label("打开隐私权限设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var clipboardStoragePanel: some View {
        panel("历史规则", systemImage: "slider.horizontal.3") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("保留条数")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    Stepper(value: $model.config.clipboardHistory.maxItems, in: 1...500, step: 10) {
                        Text("\(model.config.clipboardHistory.maxItems) 条")
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("最大长度")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    TextField("字符数", value: $model.config.clipboardHistory.maxTextLength, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("字符")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("轮询间隔")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    TextField("秒", value: $model.config.clipboardHistory.pollIntervalSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("秒")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Toggle("重启后保留历史", isOn: $model.config.clipboardHistory.persistHistory)
                    .toggleStyle(.switch)
                Toggle("忽略疑似密码或密钥内容", isOn: $model.config.clipboardHistory.ignoresSensitiveText)
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var clipboardRecentPanel: some View {
        panel("最近记录", systemImage: "clock") {
            if model.clipboardHistory.isEmpty {
                Text("暂无文本历史")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.clipboardHistory.prefix(8)) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                Text("\(item.text.count) 字")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var networkWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            restrictedWiFiOverview
            restrictedWiFiActions

            HStack(alignment: .top, spacing: 18) {
                restrictedWiFiAccountPanel
                restrictedWiFiPortalPanel
            }

            restrictedWiFiServerPanel
            restrictedWiFiDeployPanel
            activityLogPanel
        }
    }

    private var restrictedWiFiOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            statusTile(
                title: "受限 Wi-Fi",
                value: model.restrictedWiFiState,
                icon: "wifi.exclamationmark",
                tone: model.restrictedWiFiState.contains("成功") || model.restrictedWiFiState == "已联网" ? .green : .orange
            )
            statusTile(
                title: "目标网段",
                value: model.config.restrictedWiFi.targetIPPrefix,
                icon: "point.3.connected.trianglepath.dotted",
                tone: .blue
            )
            statusTile(
                title: "接码服务部署",
                value: model.wifiCodeServerDeployState,
                icon: "shippingbox.and.arrow.backward",
                tone: model.wifiCodeServerDeployState.hasPrefix("已部署") ? .green : .gray
            )
            statusTile(
                title: "接码基础域名",
                value: model.config.wifiCodeServerDeploy.baseDomain,
                icon: "globe",
                tone: .blue
            )
        }
    }

    private var restrictedWiFiActions: some View {
        panel("受限 Wi-Fi 操作", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await model.checkRestrictedWiFiConnection() }
                    } label: {
                        Label("检测联网", systemImage: "network")
                            .frame(minWidth: 104)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.requestRestrictedWiFiSMS() }
                    } label: {
                        Label("请求短信", systemImage: "envelope")
                            .frame(minWidth: 104)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await model.fetchRestrictedWiFiVerificationCodeFromServer() }
                    } label: {
                        Label("DNS 取码", systemImage: "icloud.and.arrow.down")
                            .frame(minWidth: 116)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.checkRestrictedWiFiDNSServerHealth() }
                    } label: {
                        Label("DNS 健康", systemImage: "heart.text.square")
                            .frame(minWidth: 108)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.loginRestrictedWiFiWithDNSCode() }
                    } label: {
                        Label("自动登录", systemImage: "bolt.circle")
                            .frame(minWidth: 108)
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("验证码")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    TextField("收到短信后输入", text: $model.restrictedWiFiVerificationCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Button {
                        Task { await model.loginRestrictedWiFiWithManualCode() }
                    } label: {
                        Label("登录 Wi-Fi", systemImage: "checkmark.circle")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
    }

    private var restrictedWiFiAccountPanel: some View {
        panel("账号与网络", systemImage: "person.text.rectangle") {
            VStack(spacing: 10) {
                labeledField("手机号", text: $model.config.restrictedWiFi.phoneNumber)
                labeledField("国家码", text: $model.config.restrictedWiFi.countryCode)
                labeledField("目标 IP 前缀", text: $model.config.restrictedWiFi.targetIPPrefix)
                labeledField("联网检测 URL", text: $model.config.restrictedWiFi.connectivityCheckURL)
                HStack(spacing: 10) {
                    Text("成功状态码")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    TextField("204", value: $model.config.restrictedWiFi.expectedConnectivityStatusCode, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Spacer()
                }
                Button {
                    model.save()
                } label: {
                    Label("保存网络配置", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var restrictedWiFiPortalPanel: some View {
        panel("Portal 接口", systemImage: "link") {
            VStack(spacing: 10) {
                labeledField("登录 URL", text: $model.config.restrictedWiFi.portalLoginURL)
                labeledField("Portal 页面", text: $model.config.restrictedWiFi.portalPageURL)
                labeledField("短信 API", text: $model.config.restrictedWiFi.smsAPIURL)
                labeledField("AP MAC", text: $model.config.restrictedWiFi.apMAC)
                labeledField("NAS IP", text: $model.config.restrictedWiFi.nasIP)
                labeledField("认证类型", text: $model.config.restrictedWiFi.defaultAuthType)
                labeledField("语言", text: $model.config.restrictedWiFi.language)
                labeledField("OS", text: $model.config.restrictedWiFi.os)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var restrictedWiFiServerPanel: some View {
        panel("DNS 验证码服务", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
                labeledField("验证码域名", text: $model.config.restrictedWiFi.dnsCodeLookupDomain)
                labeledField("健康检查域名", text: $model.config.restrictedWiFi.dnsHealthLookupDomain)
                labeledField("健康期望 A 记录", text: $model.config.restrictedWiFi.dnsHealthExpectedAddress)
                HStack(spacing: 10) {
                    Text("轮询设置")
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .trailing)
                    TextField("间隔秒", value: $model.config.restrictedWiFi.pollIntervalSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                    Text("秒，最多")
                        .foregroundStyle(.secondary)
                    TextField("次数", value: $model.config.restrictedWiFi.pollAttempts, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                    Text("次")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                labeledField("User-Agent", text: $model.config.restrictedWiFi.userAgent)
            }
        }
    }

    private var restrictedWiFiDeployPanel: some View {
        panel("云端接码服务部署", systemImage: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 10) {
                        labeledField("服务器地址", text: $model.config.wifiCodeServerDeploy.sshHost)
                        HStack(spacing: 10) {
                            Text("SSH 端口")
                                .foregroundStyle(.secondary)
                                .frame(width: 104, alignment: .trailing)
                            TextField("22", value: $model.config.wifiCodeServerDeploy.sshPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Spacer()
                        }
                        labeledField("SSH 用户", text: $model.config.wifiCodeServerDeploy.sshUsername)
                        HStack(spacing: 10) {
                            Text("本次密码")
                                .foregroundStyle(.secondary)
                                .frame(width: 104, alignment: .trailing)
                            SecureField("只用于本次 SSH/sudo，不保存", text: $model.wifiCodeServerDeployPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("工作目录", text: $model.config.wifiCodeServerDeploy.remoteWorkDirectory)
                        labeledField("基础域名", text: $model.config.wifiCodeServerDeploy.baseDomain)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 10) {
                        labeledField("容器名", text: $model.config.wifiCodeServerDeploy.containerName)
                        labeledField("镜像名", text: $model.config.wifiCodeServerDeploy.imageName)
                        HStack(spacing: 10) {
                            Text("服务端口")
                                .foregroundStyle(.secondary)
                                .frame(width: 104, alignment: .trailing)
                            TextField("HTTP", value: $model.config.wifiCodeServerDeploy.httpPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 86)
                            TextField("DNS", value: $model.config.wifiCodeServerDeploy.dnsPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 86)
                            Spacer()
                        }
                        Toggle("自动安装 Docker", isOn: $model.config.wifiCodeServerDeploy.allowDockerInstall)
                            .toggleStyle(.switch)
                        Toggle("允许停止已知冲突容器", isOn: $model.config.wifiCodeServerDeploy.stopConflictingKnownContainers)
                            .toggleStyle(.switch)
                        HStack(spacing: 10) {
                            Button {
                                model.applyWiFiCodeServerDomains()
                            } label: {
                                Label("写入查询域名", systemImage: "square.and.arrow.down")
                                    .frame(minWidth: 130)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await model.deployWiFiCodeServer() }
                            } label: {
                                Label("部署到云主机", systemImage: "paperplane")
                                    .frame(minWidth: 132)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                Text(model.domainSetupGuide())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !model.wifiCodeServerDeployLog.isEmpty {
                    Text(model.wifiCodeServerDeployLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var settingsWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("配置迁移", systemImage: "externaldrive") {
                Text("配置保存在用户目录下的 ~/.mac-companion/config.json。迁移电脑时复制这个文件即可。飞牛登录态由内置网页的网站数据保存，配置文件不存账号密码或 token。")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            panel("应用行为", systemImage: "dock.rectangle") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "开机启动 Mac 伴侣",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLoginEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Text("控制台打开时显示 Dock 图标；关闭窗口后隐藏 Dock 图标，菜单栏入口继续保留。")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            activityLogPanel
        }
    }

    private func placeholderWorkspace(title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            panel(title, systemImage: icon) {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            activityLogPanel
        }
    }

    private func statusTile(title: String, value: String, icon: String, tone: TileTone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tone.color.opacity(0.14))
                Image(systemName: icon)
                    .foregroundStyle(tone.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(14)
        .frame(minHeight: 90, alignment: .topLeading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func flowStep(number: String, title: String, detail: String, state: FlowState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(state.color.opacity(0.16))
                Text(number)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(state.color)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func panel<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var activityLogPanel: some View {
        panel("运行日志", systemImage: "terminal") {
            HStack(spacing: 10) {
                Text(model.logFilePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    model.openLogFolder()
                } label: {
                    Label("打开日志文件夹", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            let items = model.activityLog(for: selectedModule.logScope)
            if items.isEmpty {
                Text("暂无日志")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var feiniuLoginSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("飞牛内置网页")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(model.hasFeiniuSession ? "已检测到登录态，Mac 伴侣会直接复用它执行飞牛功能。" : "如果页面已经登录，会自动同步；首次使用建议勾选保持登录。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.hasFeiniuSession ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(model.loginState)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("完成") {
                    model.dismissFeiniuWebLogin()
                }
            }
            .padding(16)
            Divider()

            if model.feiniuWebURL != nil {
                FeiniuWebView(session: model.feiniuWebSession)
                .frame(minWidth: 980, minHeight: 640)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("飞牛 Web URL 无效")
                        .font(.headline)
                }
                .frame(width: 980, height: 640)
            }
        }
        .frame(minWidth: 980, minHeight: 700)
    }
}

private enum Module: String, CaseIterable {
    case feiniu
    case network
    case clipboard
    case automation
    case settings

    var title: String {
        switch self {
        case .feiniu: "飞牛"
        case .network: "网络工具"
        case .clipboard: "剪切板"
        case .automation: "自动化"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .feiniu: "server.rack"
        case .network: "wifi"
        case .clipboard: "clipboard"
        case .automation: "bolt"
        case .settings: "gearshape"
        }
    }

    var logScope: CompanionLogScope {
        switch self {
        case .feiniu: .feiniu
        case .network: .network
        case .clipboard: .clipboard
        case .automation: .automation
        case .settings: .settings
        }
    }
}

private enum TileTone {
    case green
    case orange
    case blue
    case gray

    var color: Color {
        switch self {
        case .green: .green
        case .orange: .orange
        case .blue: .blue
        case .gray: .secondary
        }
    }
}

private enum FlowState {
    case done
    case current
    case pending

    var color: Color {
        switch self {
        case .done: .green
        case .current: .orange
        case .pending: .secondary
        }
    }
}
