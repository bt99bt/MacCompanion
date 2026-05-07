# 我的 Mac 伴侣

一个原生 macOS 菜单栏应用雏形，用于集中放置个人常用小工具。

## 当前功能

- 菜单栏常驻入口。
- 模块化二级菜单，当前已有 `飞牛` 模块。
- Dock 图标常驻，启动和点击 Dock 会拉起桌面控制台。
- 桌面控制台作为主界面，菜单栏只保留快捷入口。
- 打开飞牛 Web 界面。
- 内置飞牛 Web 窗口，可直接网页登录。
- 从内置网页 Cookie Store 同步 `fnos-token` 到当前应用会话。
- 登录飞牛并把 `fnos-token` 保存到 macOS Keychain。
- 手动把当前公网 IPv4 添加到飞牛防火墙白名单。
- 用户配置文件：`~/.mac-companion/config.json`。

## 运行

```bash
swift run MacCompanion
```

更推荐构建成正式 macOS app 后运行，这样 Dock、WebKit 登录态和 bundle identity 更稳定：

```bash
zsh scripts/build_app.sh
open dist/MacCompanion.app
```

## 飞牛网页登录

首次使用前，先在设置里把默认飞牛地址改成你自己的 Web 界面地址、WebSocket URL 和 Origin。

推荐路径：

1. 打开桌面控制台。
2. 在飞牛模块点击 `内置网页登录`。
3. 在内置网页登录面板里正常登录飞牛。
4. 回到控制台点击 `验证连接`。
5. 点击 `添加当前 IP`。

应用会从 WebKit Cookie Store 读取 `fnos-token`，并保存在当前应用会话内，避免频繁触发 macOS 钥匙串授权弹窗。

## 飞牛接口登录配置

接口登录是备用能力。飞牛登录接口是私有协议，因此应用把登录请求做成可配置模板。

设置页里的登录字段含义：

- `登录 URL`：飞牛登录请求的完整 URL。
- `登录 Method`：通常是 `POST`。
- `Content-Type`：通常是 `application/json`。
- `登录请求体模板`：支持 `{username}` 和 `{password}` 占位符。
- `Token Cookie 名`：默认 `fnos-token`。

登录成功后，应用会从 `Set-Cookie` 或 JSON 响应里提取 `fnos-token` 并写入 Keychain。

## 防火墙白名单协议

应用通过飞牛 WebSocket 调用：

- `appcgi.security.firewall.getting`
- `appcgi.security.firewall.setting`

添加的规则为入站 TCP、全部网卡、当前公网 IP、端口 `1-65535`、允许。
