# 我的 Mac 伴侣

This README is written for a future AI agent taking over this repo. Read this first before changing code. The project is a native macOS Swift menu bar app plus a small Dockerized DNS/HTTP relay service for restricted Wi-Fi SMS verification codes.

## Current Scope

- macOS menu bar app named `MacCompanion`.
- Desktop control panel built with SwiftUI.
- Feiniu helper:
  - embedded WebKit login
  - reads `fnos-token` from WebKit cookies
  - adds current public IPv4 to Feiniu firewall whitelist
- Restricted Wi-Fi helper:
  - checks internet connectivity before doing anything
  - requests SMS code from captive portal only when not online
  - supports manual code login
  - supports DNS-based code retrieval when captive Wi-Fi blocks HTTP
- Clipboard history helper:
  - records plain-text clipboard history only
  - shows a lightweight glass-style picker near the mouse
  - supports global middle-mouse trigger, with keyboard trigger config kept in settings
  - keeps trigger diagnostics out of the visible module logs
- Cloud relay deployment:
  - app UI can deploy the code relay service to a remote Linux server
  - remote deployment uses bundled Docker image tar files
  - supports both `amd64` and `arm64` servers
  - SSH/sudo password is entered manually and must not be persisted
- Standard macOS window menu:
  - `⌘W` closes the active window
  - `⌘M` minimizes the active window
  - `⌘Q` remains the app quit shortcut

## Repository Map

```text
Package.swift
README.md
Resources/
  Info.plist
  MacCompanionIcon.svg
Sources/
  MacCompanion/
    ClipboardHistoryPanelController.swift
    ClipboardTriggerController.swift
    main.swift
  MacCompanionCore/
    AppFileLogger.swift
    ClipboardHistoryStore.swift
    ClipboardHistoryView.swift
    CompanionModel.swift
    ConfigStore.swift
    FeiniuBrowserFirewallClient.swift
    FeiniuFirewallClient.swift
    FeiniuLoginClient.swift
    FeiniuWebSession.swift
    FeiniuWebView.swift
    KeychainStore.swift
    Models.swift
    PreferencesView.swift
    PublicIPService.swift
    RestrictedWiFiLoginClient.swift
    WiFiCodeServerDeployClient.swift
  MacCompanionSelfTest/
    main.swift
  MacCompanionFeiniuSmokeTest/
    main.swift
scripts/
  build_app.sh
server/
  Dockerfile
  go.mod
  main.go
  README.md
  deploy/
    deploy_wifi_code_server_remote.sh
  images/
    wifi-code-server-amd64.tar
    wifi-code-server-arm64.tar
dist/
  MacCompanion.app
```

Important files:

- `Sources/MacCompanion/main.swift`: app delegate, menu bar item, menu actions, and standard app/window menus.
- `Sources/MacCompanion/ClipboardTriggerController.swift`: global clipboard-history trigger handling.
- `Sources/MacCompanion/ClipboardHistoryPanelController.swift`: floating clipboard picker and detail-panel placement.
- `Sources/MacCompanionCore/PreferencesView.swift`: SwiftUI control panel. The `网络工具` module contains restricted Wi-Fi login and cloud deploy UI; the `剪切板` module contains clipboard-history settings.
- `Sources/MacCompanionCore/CompanionModel.swift`: main app state and action orchestration.
- `Sources/MacCompanionCore/Models.swift`: persisted configuration schema and defaults.
- `Sources/MacCompanionCore/ClipboardHistoryStore.swift`: persisted plain-text clipboard history storage.
- `Sources/MacCompanionCore/ClipboardHistoryView.swift`: lightweight clipboard-history picker UI.
- `Sources/MacCompanionCore/RestrictedWiFiLoginClient.swift`: captive portal SMS request, portal login, connectivity check, DNS code decoding.
- `Sources/MacCompanionCore/WiFiCodeServerDeployClient.swift`: remote SSH/SCP deployment client.
- `server/main.go`: DNS/HTTP verification code relay.
- `server/deploy/deploy_wifi_code_server_remote.sh`: script executed on remote Linux servers by the app.
- `scripts/build_app.sh`: builds and signs `dist/MacCompanion.app`, and copies Docker images/scripts into app resources.

## Non-Negotiable Constraints

- Do not hardcode user-specific server address, SSH username, password, root password, or domain in code.
- SSH/sudo password may be accepted in the UI for one deployment run, but must remain memory-only and must not be saved to `~/.mac-companion/config.json`.
- Keep key fields configurable through `Models.swift` and `PreferencesView.swift`.
- In restricted Wi-Fi auto-login, always check connectivity first. If already online, do not request SMS.
- Captive Wi-Fi may block HTTP but allow DNS. Code retrieval and health checks must work through DNS.
- Do not remove manual verification-code login; it is the current fallback path before the server is fully wired.
- Do not silently kill unknown remote services when ports are occupied. Only stop known containers when the user enables that option.
- The app is not sandboxed for App Store distribution; it relies on local `ssh`, `scp`, `codesign`, WebKit, and shell tooling.

## Build And Test

Use these commands from repo root.

Build:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache swift build --disable-sandbox
```

Self-test:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache swift run --disable-sandbox MacCompanionSelfTest
```

Build app bundle:

```bash
zsh scripts/build_app.sh
```

Open app:

```bash
open dist/MacCompanion.app
```

Verify signature:

```bash
codesign --verify --deep --strict --verbose=2 dist/MacCompanion.app
```

Why the cache env var matters:

- The default Swift/Clang cache may point at `~/.cache/clang`, which can fail under Codex sandboxing with `Operation not permitted`.
- The known-good workaround is `CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache`.

Why `scripts/build_app.sh` may need escalation:

- It uses `qlmanage` to render the SVG icon into PNG/iconset/icns.
- In the Codex sandbox, `qlmanage` can fail with `sandbox initialization failed: invalid data type of path filter`.
- Running `zsh scripts/build_app.sh` outside the sandbox fixes it.

## Packaging Details

`scripts/build_app.sh` does all of this:

1. Runs `swift build --disable-sandbox`.
2. Creates `dist/MacCompanion.app`.
3. Generates `MacCompanion.icns` from `Resources/MacCompanionIcon.svg`.
4. Copies the executable and `Resources/Info.plist`.
5. Copies Docker image tar files into:

```text
dist/MacCompanion.app/Contents/Resources/WifiCodeServerImages/
```

6. Copies remote deploy scripts into:

```text
dist/MacCompanion.app/Contents/Resources/WifiCodeServerDeploy/
```

7. Runs local ad-hoc codesign:

```bash
codesign --force --deep --sign - dist/MacCompanion.app
```

If the app crashes immediately with `MacCompanion quit unexpectedly`, inspect:

```text
~/Library/Logs/DiagnosticReports/
```

If the crash is `SIGKILL` with `Code Signature Invalid`, rebuild/sign the app. This previously happened after manually replacing the executable inside `.app`.

## Configuration

User config is stored at:

```text
~/.mac-companion/config.json
```

Config schema lives in `Sources/MacCompanionCore/Models.swift`.

Persisted:

- Feiniu URLs and cookie name.
- Restricted Wi-Fi phone number and portal endpoints.
- DNS code lookup domain.
- DNS health domain and expected A record.
- Remote deploy host, SSH port, SSH username, work directory, base domain, container/image/port settings.
- Clipboard history settings: enabled state, persistence, max items, max text length, poll interval, sensitive-text filtering flag, and trigger config.

Never persisted:

- SSH password.
- sudo password.
- Wi-Fi SMS verification code.
- Feiniu session token from WebKit flow.

Clipboard history is stored separately at:

```text
~/.mac-companion/clipboard-history.json
```

It stores plain text plus local metadata such as creation time and use count. It must not store rich text, files, images, or password-like content unless the user explicitly disables filtering.

Note: `FeiniuLoginClient` can store a token in Keychain for the old direct API-login path, but the preferred current flow is embedded WebKit login via `FeiniuWebSession`.

## Restricted Wi-Fi Flow

The implementation is based on the user's previous project:

```text
https://github.com/bt99bt/wifi_auto_login/tree/main/src
```

Relevant old-project concepts mirrored here:

- connectivity check: `http://connect.rom.miui.com/generate_204`, expect HTTP `204`
- SMS request through captive portal API
- portal login with phone number and SMS code
- DNS code decode format: `1.x.y.z` -> six-digit code

Current app flow:

1. User clicks `检测联网` or `自动登录`.
2. `RestrictedWiFiLoginClient.checkInternetConnection()` sends GET to configured connectivity URL.
3. Redirects are disabled. A captive portal redirect should not be treated as success.
4. If already online, automatic login returns immediately and must not request SMS.
5. If offline/captive, `requestSMS()` calls the configured SMS API.
6. Manual path: user enters code and calls `login(code:)`.
7. DNS path: app polls `fetchVerificationCodeFromDNS()`, then calls `login(code:)`.
8. After login request, app checks connectivity again.

Configurable fields are exposed in the `网络工具` UI. Avoid hiding behavior in code constants.

## Captive Portal Request Details

`RestrictedWiFiLoginClient` builds requests using config values:

- phone number and country code
- target local IP prefix, default `10.50.`
- portal login URL
- portal page URL
- SMS API URL
- AP MAC
- NAS IP
- auth type
- language
- OS
- user agent
- poll interval and attempts

`localIPv4()` scans local interfaces and picks an IPv4 address matching `targetIPPrefix`. If login fails with local IP errors, check the configured prefix first.

`Resources/Info.plist` includes an ATS exception for the HTTP connectivity-check host. Do not enable broad arbitrary loads unless absolutely necessary.

## DNS Code Relay Protocol

The relay exists because restricted Wi-Fi can block HTTP before login while DNS still works.

Server HTTP endpoints:

```text
GET /push?code=123456
GET /push/123456
GET /code
GET /health
```

Server DNS endpoints:

```text
code.<BASE_DOMAIN>    A  1.xx.yy.zz
health.<BASE_DOMAIN>  A  1.255.255.255
```

Encoding:

```text
123456 -> 1.12.34.56
000001 -> 1.0.0.1
654321 -> 1.65.43.21
```

No code stored:

```text
code.<BASE_DOMAIN> -> 0.0.0.0
```

Service policy:

- Stores only one latest code in memory.
- New code overwrites old code.
- Reading the code does not delete it.
- No auth.
- No persistence.
- Six-digit codes only.

## DNS Health Check

The app checks:

```text
health.<BASE_DOMAIN> A == 1.255.255.255
```

In `RestrictedWiFiLoginClient.checkDNSServerHealth()`, the app currently uses system `getaddrinfo`. This means local DNS proxy behavior can affect results.

Known fake-ip issue:

- Some local proxy/TUN setups return `198.18.0.0/15` fake IPs.
- In that case, DNS health may show fake-ip even though the remote DNS service is fine.
- Add bypass/direct rules for:

```text
<BASE_DOMAIN>
*.<BASE_DOMAIN>
code.<BASE_DOMAIN>
health.<BASE_DOMAIN>
```

The app summary already tries to identify fake-ip results so the UI error is less misleading.

## Domain Delegation

The intended deployment uses subdomain NS delegation.

Example base domain:

```text
code.example.com
```

Domain console records:

```text
code      NS    ns.code.example.com
ns.code   A     <server public IPv4>
```

Then Mac Companion should query:

```text
code.code.example.com
health.code.example.com
```

The double `code` is intentional:

- `code.example.com` is the delegated base domain.
- `code.code.example.com` is the verification-code A record inside that delegated zone.

Debug commands:

```bash
dig @<server public IPv4> +short health.code.example.com A
dig +short health.code.example.com A
dig @<server public IPv4> +short code.code.example.com A
```

Expected:

```text
1.255.255.255
```

for health, and `1.xx.yy.zz` for a pushed code.

## iPhone Shortcut Flow

The submitter is an iPhone Shortcut triggered after receiving an SMS.

Use the simplest HTTP GET format:

```text
http://<server public IPv4>:8080/push?code=123456
```

or:

```text
http://<server public IPv4>:8080/push/123456
```

No auth is expected. Do not add auth unless the user explicitly changes this requirement.

## Cloud Deploy UI

UI lives in `PreferencesView.restrictedWiFiDeployPanel`.

State/actions live in `CompanionModel`:

- `wifiCodeServerDeployPassword`
- `wifiCodeServerDeployState`
- `wifiCodeServerDeployLog`
- `deployWiFiCodeServer()`
- `applyWiFiCodeServerDomains()`
- `domainSetupGuide()`

Deployment client:

```text
Sources/MacCompanionCore/WiFiCodeServerDeployClient.swift
```

The deploy client:

1. Validates host, user, port, password, work directory, base domain.
2. Uses system `/usr/bin/ssh` and `/usr/bin/scp`.
3. Creates a temporary `SSH_ASKPASS` script containing the password.
4. Deletes the temporary askpass directory after deployment.
5. Runs `uname -m` remotely.
6. Chooses image tar:
   - `x86_64` or `amd64`: `wifi-code-server-amd64.tar`
   - `aarch64` or `arm64`: `wifi-code-server-arm64.tar`
7. Resolves `~/...` remote work directory using remote `$HOME`.
8. Uploads image tar and deploy script.
9. Runs the deploy script through `sudo -S`.
10. Clears `wifiCodeServerDeployPassword` after success.

Security note:

- The current implementation passes password to SSH via temporary askpass and to remote sudo via stdin.
- Do not log the password.
- Do not put the password into `Process.arguments`, README examples, config, or shell command strings.

## Remote Deploy Script

Remote script:

```text
server/deploy/deploy_wifi_code_server_remote.sh
```

Expected env:

```text
BASE_DOMAIN
CONTAINER_NAME
IMAGE_NAME
HTTP_PORT
DNS_PORT
ALLOW_DOCKER_INSTALL
STOP_KNOWN_CONFLICTS
IMAGE_TAR
```

Default runtime ports:

```text
53/udp
53/tcp
8080/tcp
```

Behavior:

- Installs Docker automatically via `apt-get`, `yum`, or `dnf` if Docker is missing and `ALLOW_DOCKER_INSTALL=1`.
- Removes existing container with the configured container name.
- Optionally stops known old conflicting container `shadow-radio`.
- Checks port occupancy with `ss` or `netstat`.
- Loads the selected tar using `docker load -i`.
- Starts container with restart policy `unless-stopped`.
- Prints Docker status.
- Checks HTTP health on `127.0.0.1`.
- Checks DNS health with `dig` if available.

Do not change it to kill arbitrary processes. If unknown ports conflict, surface the error to the user.

## Server Code

Go service in `server/main.go`.

Runtime config:

```text
HTTP_ADDR=:8080
DNS_ADDR=:53
BASE_DOMAIN=wifi-code.example.com
CODE_DOMAIN=code.<BASE_DOMAIN>
HEALTH_DOMAIN=health.<BASE_DOMAIN>
HEALTH_ADDRESS=1.255.255.255
EMPTY_ADDRESS=0.0.0.0
DEFAULT_DNS_REPLY=0.0.0.0
```

Implementation details:

- Standard library only.
- Implements minimal DNS UDP and TCP response handling.
- Only answers A records.
- TTL is currently 5 seconds.
- Unknown A queries return `DEFAULT_DNS_REPLY`.
- Unsupported query types return no answer.

Build images:

```bash
docker build --platform linux/amd64 -t wifi-code-server:latest server
docker save wifi-code-server:latest -o server/images/wifi-code-server-amd64.tar
docker build --platform linux/arm64 -t wifi-code-server:latest server
docker save wifi-code-server:latest -o server/images/wifi-code-server-arm64.tar
```

Important Dockerfile detail:

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS build
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build ...
```

This avoids `exec format error` when building an arm64 image on an amd64 server without QEMU emulation.

## Feiniu Flow

Preferred user flow:

1. Open desktop control panel.
2. In `飞牛`, open the embedded web panel.
3. Log in normally.
4. App reads the configured token cookie from WebKit Cookie Store.
5. `verifyFeiniuFirewallConnection()` checks firewall summary.
6. `addCurrentIPToFeiniuFirewall()` fetches current public IPv4 and adds an allow rule.

Key files:

- `FeiniuWebSession.swift`: WebKit cookie sync and firewall API session.
- `FeiniuWebView.swift`: embedded WebView.
- `FeiniuBrowserFirewallClient.swift`: browser-authenticated firewall calls.
- `PublicIPService.swift`: fetches public IPv4.

Be careful with WebKit state and app identity. Running as a proper `.app` bundle is more stable than `swift run` for WebKit/cookie behavior.

## Clipboard History

The clipboard feature records only `NSPasteboard` plain-text values.

Runtime pieces:

- `ClipboardTriggerController` registers the global trigger.
- `ClipboardHistoryPanelController` owns the floating picker window and hover detail window.
- `ClipboardHistoryView` renders the compact list of recent items.
- `ClipboardHistoryStore` persists history to `~/.mac-companion/clipboard-history.json`.

Trigger behavior:

- Default trigger mode is middle mouse.
- `CGEventTap` is attempted first so the middle-click event can be swallowed when macOS permissions allow it.
- If the writable event tap is unavailable, the app falls back to listen-only monitoring so the picker can still appear.
- Global middle-mouse listening requires macOS privacy permission under Input Monitoring. Because the app is ad-hoc signed during local builds, rebuilding or replacing the `.app` can require re-granting privacy permissions.

UI behavior:

- The picker appears near the mouse and shows the most recent plain-text entries.
- Selecting an item writes it back to the system clipboard; it does not auto-paste.
- The picker uses SwiftUI liquid glass styling. Avoid adding large shadows around transparent `NSPanel` windows because they can create gray corner artifacts.
- Placement uses the screen visible frame; if Dock-related offsets are adjusted, verify both below-mouse and above-mouse placement.

## Logging

Runtime log path is exposed in the UI and backed by `AppFileLogger`.

The UI activity log is in-memory, capped, and scoped by module. Do not send high-frequency diagnostics such as clipboard mouse-event traces into the user-visible status or activity log; write them to `AppFileLogger` with a category instead. Persistent file logs are better for debugging longer flows.

Useful places:

```text
~/.mac-companion/
~/Library/Logs/DiagnosticReports/
```

## Known Good Current Verification

At the time this README was rewritten:

- `swift build --disable-sandbox` passed with `CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache`.
- `swift run --disable-sandbox MacCompanionSelfTest` passed.
- `zsh scripts/build_app.sh` passed when run outside sandbox.
- `codesign --verify --deep --strict --verbose=2 dist/MacCompanion.app` passed.
- `dist/MacCompanion.app` contains:

```text
Contents/Resources/WifiCodeServerImages/wifi-code-server-amd64.tar
Contents/Resources/WifiCodeServerImages/wifi-code-server-arm64.tar
Contents/Resources/WifiCodeServerDeploy/deploy_wifi_code_server_remote.sh
```

- A real remote redeploy was tested successfully.
- Remote local DNS health returned `1.255.255.255`.
- Local machine DNS showed fake-ip `198.18.x.x`, caused by local proxy/TUN rewriting.

## Troubleshooting Checklist

If automatic Wi-Fi login sends SMS while already online:

- Inspect `CompanionModel.loginRestrictedWiFiWithDNSCode()`.
- It must call `checkInternetConnection()` first and return if online.

If connectivity check fails with ATS:

- Inspect `Resources/Info.plist`.
- There is a scoped ATS exception for `connect.rom.miui.com`.

If DNS health is abnormal:

- Query the authoritative server directly:

```bash
dig @<server public IPv4> +short health.<BASE_DOMAIN> A
```

- If direct query is good but system query is fake-ip, adjust local proxy bypass.

If remote deploy fails at SSH password:

- Check `WiFiCodeServerDeployClient`.
- It depends on `/usr/bin/ssh`, `/usr/bin/scp`, `SSH_ASKPASS`, and `SSH_ASKPASS_REQUIRE=force`.
- Password must not be stored.

If remote deploy fails at sudo:

- The SSH user must have sudo permission.
- The app sends the one-time password to `sudo -S` over stdin.

If remote deploy fails at Docker:

- Check remote output from `wifiCodeServerDeployLog`.
- Docker installation requires `apt-get`, `yum`, or `dnf`.
- Ports `53/tcp`, `53/udp`, `8080/tcp` must be available.

If arm64 image build fails with `exec format error`:

- Ensure Dockerfile uses `FROM --platform=$BUILDPLATFORM` for the Go build stage.
- Ensure `GOARCH=${TARGETARCH}` is set.

If app crashes after manual packaging:

- Run:

```bash
codesign --force --deep --sign - dist/MacCompanion.app
codesign --verify --deep --strict --verbose=2 dist/MacCompanion.app
```

If UI fields look prefilled with user-specific values:

- Check `AppConfig.default` in `Models.swift`.
- Defaults must not include private hostnames, usernames, passwords, or personal domains.

## Agent Editing Guidelines

- Prefer small, focused changes.
- Keep user-specific values out of source defaults and documentation examples.
- Preserve manual-code flow.
- Preserve DNS-code flow.
- Preserve server-code module placeholders where they support future server integration.
- When adding config fields, update:
  - `Models.swift`
  - `AppConfig.default`
  - decoding defaults
  - `PreferencesView.swift`
  - README if behavior changes
- When changing deploy resources, update:
  - `server/deploy/deploy_wifi_code_server_remote.sh`
  - `scripts/build_app.sh`
  - app resource lookup in `WiFiCodeServerDeployClient.swift`
- After code changes, run build and self-test.
- After packaging changes, run build app and codesign verification.
