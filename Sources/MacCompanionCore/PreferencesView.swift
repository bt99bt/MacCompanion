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
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
        .frame(width: 232)
        .background(Color(nsColor: .controlBackgroundColor))
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
            .background(selectedModule == module ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        placeholderWorkspace(
                            title: "网络工具",
                            icon: "wifi",
                            detail: "这里会放 Wi-Fi 信息、DNS 检测、端口连通性、路由追踪和常用网络修复动作。"
                        )
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
                Text(model.status)
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

                    Text("应用默认显示 Dock 图标，并在启动或点击 Dock 时拉起控制台。菜单栏保留常驻快捷入口。")
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            if model.activityLog.isEmpty {
                Text("暂无日志")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.activityLog, id: \.self) { item in
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
    case automation
    case settings

    var title: String {
        switch self {
        case .feiniu: "飞牛"
        case .network: "网络工具"
        case .automation: "自动化"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .feiniu: "server.rack"
        case .network: "wifi"
        case .automation: "bolt"
        case .settings: "gearshape"
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
