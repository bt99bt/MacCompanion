# MacCompanion Context For Resume

This file captures the current working context for another AI agent. It intentionally does not include SSH passwords, sudo passwords, root passwords, or other secrets.

## Project Summary

`MacCompanion` is a native macOS Swift menu bar app with a SwiftUI control panel. It currently contains:

- Feiniu helper for embedded WebKit login and firewall whitelist management.
- Restricted Wi-Fi helper for captive portal SMS-code login.
- DNS-based verification-code retrieval because captive Wi-Fi may block HTTP before login but still allow DNS.
- Cloud deployment UI for a Dockerized SMS-code relay service.
- Bundled `amd64` and `arm64` Docker image tar files so the app can deploy the relay service from another Mac.

## Current Branch And Remote

- Current branch: `main`
- Remote: `origin` -> `https://bt99bt@github.com/bt99bt/MacCompanion.git`

## Important Files

- `Sources/MacCompanion/main.swift`
  - macOS app delegate, menu bar item, menu actions.
- `Sources/MacCompanionCore/Models.swift`
  - `AppConfig`, `RestrictedWiFiConfig`, `WiFiCodeServerDeployConfig`.
  - Defaults must not include private hostnames, usernames, passwords, or personal domains.
- `Sources/MacCompanionCore/CompanionModel.swift`
  - Main state and orchestration for Feiniu, restricted Wi-Fi, DNS-code login, and cloud deploy.
- `Sources/MacCompanionCore/PreferencesView.swift`
  - SwiftUI control panel. `网络工具` contains restricted Wi-Fi login and cloud deployment UI.
- `Sources/MacCompanionCore/RestrictedWiFiLoginClient.swift`
  - Connectivity check, SMS request, portal login, DNS health check, DNS code decoding.
- `Sources/MacCompanionCore/WiFiCodeServerDeployClient.swift`
  - Uses `/usr/bin/ssh` and `/usr/bin/scp` to deploy the Docker service to a Linux server.
  - Uses temporary `SSH_ASKPASS` for one-time password input and deletes it afterwards.
- `server/main.go`
  - Go HTTP/DNS relay service.
- `server/Dockerfile`
  - Multi-stage cross-platform Docker build.
- `server/deploy/deploy_wifi_code_server_remote.sh`
  - Remote script copied to and executed on the cloud server.
- `server/images/`
  - Bundled image tar files:
    - `wifi-code-server-amd64.tar`
    - `wifi-code-server-arm64.tar`
- `scripts/build_app.sh`
  - Builds the Swift app, copies server resources into `.app`, and ad-hoc signs it.
- `README.md`
  - Rewritten as a full AI-agent-oriented project/debugging handoff.

## Recent Feature Work

Restricted Wi-Fi:

- Added configurable captive portal login module.
- Added manual verification-code login flow.
- Added DNS-code retrieval flow.
- Added automatic login flow that first checks connectivity. If already online, it returns without requesting SMS.
- Added DNS health check for the code relay server.
- Added ATS exception for the HTTP 204 connectivity endpoint.

Cloud code relay:

- Added Go relay service with HTTP endpoints for iPhone Shortcuts and DNS A-record responses for Mac Companion.
- Added Dockerfile and remote deployment script.
- Added Mac Companion UI to deploy the relay service to a remote Linux server.
- Deployment chooses `amd64` or `arm64` image based on remote `uname -m`.
- Password is entered in the UI for the current run only and must not be persisted.
- Docker may be installed automatically on the remote server.
- Unknown port conflicts are surfaced rather than silently killed.

Docs:

- Root `README.md` now explains project structure, build/test/package commands, known pitfalls, DNS relay protocol, cloud deployment, and troubleshooting.
- `server/README.md` points back to the root README.

## DNS Relay Protocol

The relay exists because restricted Wi-Fi may allow DNS while blocking HTTP.

HTTP endpoints:

```text
GET /push?code=123456
GET /push/123456
GET /code
GET /health
```

DNS endpoints:

```text
code.<BASE_DOMAIN>    A  1.xx.yy.zz
health.<BASE_DOMAIN>  A  1.255.255.255
```

Encoding examples:

```text
123456 -> 1.12.34.56
000001 -> 1.0.0.1
654321 -> 1.65.43.21
```

No code stored:

```text
code.<BASE_DOMAIN> -> 0.0.0.0
```

Service behavior:

- Only one latest code is stored.
- New code overwrites old code.
- Reading the code does not delete it.
- No auth.
- No persistence.
- Six-digit codes only.

## Domain Delegation Model

Example base domain:

```text
code.example.com
```

DNS console records:

```text
code      NS    ns.code.example.com
ns.code   A     <server public IPv4>
```

Mac Companion query domains:

```text
code.code.example.com
health.code.example.com
```

The double `code` is intentional:

- `code.example.com` is the delegated base domain.
- `code.code.example.com` is the verification-code A record inside that zone.

## Known Verified State

At the time this context file was written:

- Swift build passed:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache swift build --disable-sandbox
```

- Self-test passed:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache swift run --disable-sandbox MacCompanionSelfTest
```

- App bundle build passed when run outside sandbox:

```bash
zsh scripts/build_app.sh
```

- App signature verified:

```bash
codesign --verify --deep --strict --verbose=2 dist/MacCompanion.app
```

- `dist/MacCompanion.app` includes:

```text
Contents/Resources/WifiCodeServerImages/wifi-code-server-amd64.tar
Contents/Resources/WifiCodeServerImages/wifi-code-server-arm64.tar
Contents/Resources/WifiCodeServerDeploy/deploy_wifi_code_server_remote.sh
```

- Real remote redeploy was tested successfully.
- Remote local DNS health returned `1.255.255.255`.
- Local Mac DNS may show `198.18.x.x` due to local fake-ip proxy/TUN behavior.

## Build And Test Notes

Use:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache swift build --disable-sandbox
env CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache swift run --disable-sandbox MacCompanionSelfTest
```

`scripts/build_app.sh` may need to run outside the Codex sandbox because `qlmanage` can fail inside sandbox with:

```text
sandbox initialization failed: invalid data type of path filter; expected pattern, got boolean
```

If the app crashes immediately after manual packaging, check DiagnosticReports for `Code Signature Invalid`, then run:

```bash
codesign --force --deep --sign - dist/MacCompanion.app
codesign --verify --deep --strict --verbose=2 dist/MacCompanion.app
```

## Debugging Checklist

If auto-login requests SMS while already online:

- Check `CompanionModel.loginRestrictedWiFiWithDNSCode()`.
- It must call `checkInternetConnection()` first and return if online.

If DNS health fails:

- Query the authoritative server directly:

```bash
dig @<server public IPv4> +short health.<BASE_DOMAIN> A
```

- If direct query works but local query returns `198.18.x.x`, add fake-ip bypass/direct rules for the relay domain.

If remote deploy fails:

- Check `wifiCodeServerDeployLog` in the UI.
- Check `WiFiCodeServerDeployClient.swift` for SSH/SCP behavior.
- The remote SSH user must have sudo permission.
- Ports required: `53/udp`, `53/tcp`, `8080/tcp`.

If arm64 Docker build fails with `exec format error`:

- Ensure Dockerfile uses `FROM --platform=$BUILDPLATFORM` for the build stage.
- Ensure `GOARCH=${TARGETARCH}` is used during Go build.

## Security Notes

- Do not commit secrets.
- Do not write SSH/sudo passwords to config, README, context files, process arguments, or logs.
- Do not add auth to the iPhone Shortcut `/push` flow unless the user explicitly requests a design change.
- Do not hardcode server host, user, password, or domain in app defaults.

## Suggested Follow-Up Areas

- Add automated unit tests for DNS code encode/decode.
- Add a remote deploy dry-run mode.
- Improve deployment log streaming in the UI.
- Consider direct DNS query implementation for health checks to bypass local system fake-ip behavior when appropriate.
