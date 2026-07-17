<p align="center">
 <img width="1926" height="1028" alt="AI-Usage-linkedin" src="https://github.com/user-attachments/assets/4509bcb3-a1ff-4ab3-8751-4bee65a7e83f" />
</p>

# AI Usage

A native macOS menu bar app — with a desktop widget, an iOS companion and an Apple Watch app — to keep an eye on your AI assistant usage — **Claude**, **OpenAI**, **OpenCode** and **DeepSeek** — without leaving the keyboard: plan limits at a glance, token counts, cost and prepaid balance.

## Download

**[⬇ Download AI Usage.dmg](https://github.com/aitorsola/AI-Usage/releases/latest/download/AI-Usage.dmg)** — open the `.dmg` and drag **AI Usage** into your Applications folder.

Universal build (Apple Silicon + Intel), signed with a Developer ID certificate and notarized by Apple, so it opens without Gatekeeper warnings. Requires macOS 14 or later. Prefer to compile it yourself? See [Build from source](#build-from-source).

## Features

- **Menu bar at a glance** — remaining percentage of your session and weekly limits (e.g. `✳ 63% · 87%`). Configurable: remaining vs. used, and which provider drives the number — Claude, OpenAI, OpenCode (today's tokens), DeepSeek (balance) or today's total cost.
- **Four providers, one panel**
  - **Claude** — token usage and cost parsed from local Claude Code transcripts; live plan limits (5-hour session, weekly, per-model) from Anthropic's usage endpoint.
  - **OpenAI** — token usage from local Codex CLI sessions; live rate limits, plan, credits and spend caps from the ChatGPT backend.
  - **OpenCode** — token usage and cost read from OpenCode's local database, broken down by model. OpenCode has no subscription, so there are no percentages — just tokens and cost (which OpenCode itself has already computed).
  - **DeepSeek** — prepaid API balance from DeepSeek's official endpoint, using an API key you paste in.
- **Dashboard window** — per-provider tabs with today / current block / 7-day / 30-day cards, plan limit gauges, daily history bars and a per-model breakdown.
- **Desktop widget** — a WidgetKit widget that mirrors the panel on your desktop or Notification Center, in three sizes: *small* shows your primary provider's session and weekly gauges with reset countdowns; *medium* keeps the first provider with today's cost and tokens; *large* mirrors the whole panel — every enabled provider plus the 7-day chart (shown only when the weekly section is on). Clicking any widget opens the dashboard (`aiusage://` deep link). App and widget share a ready-to-render snapshot through an App Group.
- **iOS companion app** — an iPhone/iPad app (built from the same repo and shared core) that signs in with the same OAuth flows and shows live plan limits for Claude and OpenAI plus the DeepSeek balance. iOS has no local CLI logs, so token/cost history stays a macOS feature. Includes a **Home Screen widget** with the session and weekly gauges and their reset countdowns.
- **Apple Watch app** — fully self-updating: the iPhone hands the credentials over once (WatchConnectivity, encrypted between paired devices — watchOS can't run the browser OAuth flows), and from then on the watch fetches plan limits on its own, on foreground and via periodic background refresh, so the complication stays fresh even with the phone away. Shows every signed-in provider with its session and weekly bars and reset info, following the remaining/used mode set in the host app. Plus a **fitness-rings style complication** for the first provider — session ring in the provider's color, weekly ring in gray, with two tiny center percentages color-matched to their ring so each quota is unmistakable.
- **Plan extras, only when they exist** — Claude extra usage (monthly overage in dollars), OpenAI credits balance, individual spend limits, DeepSeek balance, and a red banner with the reason whenever a limit is hit. Empty data never renders empty UI, and the widgets surface a status note (signed out, fetch failed) instead of going silently blank.
- **Three ways to connect**
  - **Browser OAuth** (Claude, OpenAI) — OAuth 2.0 + PKCE with a local callback server, the same public flows used by Claude Code (port 54545) and Codex CLI (port 1455). The app never reads other apps' credentials, so macOS never shows keychain permission prompts.
  - **API key** (DeepSeek) — pasted in Settings and stored in the app's own Keychain item; only used to read your balance. Invalid keys are detected and flagged.
  - **No sign-in** (OpenCode) — usage is read straight from the local database.
- **Menu customization** — sections (Claude / OpenAI / OpenCode / DeepSeek / last 7 days) can be hidden and reordered. Sections with no data or session stay hidden automatically. Right-click the menu bar icon for a quick context menu (open, refresh, settings, quit).
- **Localized** — Spanish, English, French, German, Italian, Portuguese, Japanese, Simplified Chinese, Korean and Russian. Follows the system language.
- **Launch at login**, automatic refresh every 60 seconds, incremental file parsing (only re-reads changed session files).

## Requirements

- macOS 14 or later (Apple Silicon and Intel); the iOS companion targets iOS 17+ and the watch app watchOS 10+.
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the generated project uses synchronized folder references and bundles six targets: app + widget for macOS, iOS and watchOS, all linked against the `AIUsageCore` Swift package.

## Build from source

### macOS

```sh
brew install xcodegen   # once
./build_xcode.sh
open "/Applications/AI Usage.app"
```

`build_xcode.sh` generates the icon asset catalog, runs XcodeGen to produce `AIUsage.xcodeproj` from `project.yml`, builds the app and the widget extension, signs both bundles manually and installs `AI Usage.app` into `/Applications`. Signing picks, in order: the `CODESIGN_IDENTITY` environment variable, the first *Apple Development* identity in your keychain, or an ad-hoc signature. A stable identity is recommended so Keychain approvals survive rebuilds. The app and widget share data through the `group.dev.aitor.ai-usage` App Group, so both targets are signed with matching entitlements from `Signing/`.

### iOS

The iOS app is not distributed (no App Store / TestFlight yet) — build it from Xcode:

```sh
xcodegen generate       # if you haven't run build_xcode.sh yet
open AIUsage.xcodeproj
```

Select the **AIUsageiOS** scheme and run it on your device or the simulator. The iOS targets use automatic signing: to run on a device, change `DEVELOPMENT_TEAM` in `project.yml` (or the Signing & Capabilities tab) to your own team — the App Group used by the widget requires a paid developer account.

The **Apple Watch app ships embedded in the iOS app** (or run the `AIUsageWatch` scheme against a paired watch). Development installs need the watch registered as a device in your developer account and **Developer Mode enabled on the watch itself** (Settings → Privacy & Security → Developer Mode — note this is a different menu from Settings → Developer).

## Tests

Three layers, ~70 tests in total:

```sh
# Cross-platform core (no Xcode needed): aggregation, pricing, formatters,
# rate-limit parsing, OAuth/PKCE/JWT, localization consistency, widget snapshot.
cd AIUsageCore && swift test

# macOS target: local log parsers (Claude transcripts, Codex sessions and an
# on-disk SQLite fixture for OpenCode), demo data and store logic.
xcodebuild test -scheme AIUsage -destination 'platform=macOS'

# iOS target: brand color mapping and login coordinator.
xcodebuild test -scheme AIUsageiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

Both schemes also run their suite from Xcode with **Cmd+U**.

## How it works

### Data sources

| Provider | Tokens & cost | Limits / balance |
|---|---|---|
| **Claude** | `~/.claude/projects/**/*.jsonl` (Claude Code transcripts) | `api.anthropic.com/api/oauth/usage` + `/api/oauth/profile` |
| **OpenAI** | `~/.codex/sessions/**/*.jsonl` (Codex CLI sessions) | `chatgpt.com/backend-api/wham/usage` |
| **OpenCode** | `~/.local/share/opencode/opencode.db` (SQLite, read-only) | — (no subscription) |
| **DeepSeek** | — (no local logs) | `api.deepseek.com/user/balance` (prepaid balance) |

- Cost figures for Claude and OpenAI are **API-equivalent estimates** computed from per-model pricing (including cache write/read multipliers for Claude and cached-input pricing for OpenAI). Subscription plans don't bill per token — treat the number as a consumption gauge. OpenCode reports its own cost per session, so that figure is used as-is.
- Plan limits come exclusively from the provider endpoints, using your own session. Duplicate transcript entries are deduplicated by message and request id.
- On **iOS** only the endpoint columns apply: the local logs live on your Mac, so the companion app shows plan limits and balance but no token/cost history (and OpenCode, being fully local, is macOS-only).

### Authentication

Claude and OpenAI use their public OAuth clients with the standard PKCE flow. Sign-in opens the browser; the authorization redirects back to a loopback server bound to the same port each CLI uses. Access/refresh tokens are stored under dedicated Keychain items (`AI Usage-credentials`, `AI Usage-openai-credentials`) and refreshed transparently before expiry. Signing out deletes the item. For OpenAI, if a plaintext `~/.codex/auth.json` exists (older Codex CLI versions), it is used as a fallback session.

DeepSeek uses a personal API key (from `platform.deepseek.com`) stored in its own Keychain item (`AI Usage-deepseek-key`); it is only ever sent to DeepSeek to read your balance.

OpenCode requires no authentication — its usage lives in a local SQLite database, opened read-only.

### Privacy

Everything runs locally. The only network requests are the usage/profile/balance calls to Anthropic, OpenAI and DeepSeek described above, authenticated with your own session or key. No analytics, no telemetry, no third-party services.

## Project layout

```
├── project.yml                     # XcodeGen spec (macOS + iOS app & widget targets)
├── build_xcode.sh                  # Generate project, build, sign, install locally (macOS)
├── release.sh                      # Universal build → Developer ID sign → notarize → .dmg
├── scripts/
│   └── make_icon.swift             # Generates the app icon (macOS and iOS variants)
├── AIUsageCore/                    # Swift package: cross-platform core, linked by all targets
│   ├── Package.swift
│   ├── Sources/AIUsageCore/
│   │   ├── Models/
│   │   │   ├── Models.swift             # Core usage / plan data types
│   │   │   └── AppSettings.swift        # Settings keys, menu-section configuration
│   │   ├── Providers/
│   │   │   ├── Anthropic/               # Claude: OAuth PKCE + usage/profile endpoints
│   │   │   │   ├── AnthropicAuth.swift
│   │   │   │   └── PlanFetcher.swift
│   │   │   ├── OpenAI/                  # OpenAI: OAuth PKCE + usage endpoint
│   │   │   │   ├── OpenAIAuth.swift
│   │   │   │   └── RateLimitParsing.swift  # Rate-limit payload decoding (logs + endpoint)
│   │   │   └── DeepSeek/
│   │   │       └── DeepSeekAuth.swift   # API key store + balance endpoint
│   │   ├── Aggregator.swift             # Rolls parsed entries into periods and totals
│   │   ├── Pricing.swift                # Per-model price tables
│   │   ├── Support/
│   │   │   └── Formatters.swift         # Number, date and cost formatting
│   │   ├── Localization.swift           # Language detection + translation catalog
│   │   └── WidgetShared.swift           # App-Group snapshot model
│   └── Tests/AIUsageCoreTests/          # swift test — 46 unit tests over the core
├── macOS/                          # Menu bar app
│   ├── App/
│   │   ├── AIUsageApp.swift             # App entry point, scenes, widget deep link
│   │   └── StatusItemMenu.swift         # Menu bar icon + right-click context menu
│   ├── Core/
│   │   ├── UsageStore.swift             # Refresh loop, provider state, widget snapshot
│   │   └── DemoData.swift               # Fabricated data for screenshots (-demo flag)
│   ├── Parsers/                         # Local CLI log parsers (macOS only)
│   │   ├── UsageParser.swift            # Claude Code transcripts
│   │   ├── CodexParser.swift            # Codex CLI sessions
│   │   └── OpenCodeParser.swift         # OpenCode SQLite database
│   └── Views/
│       ├── MenuContentView.swift        # Menu bar dropdown + status label
│       ├── DashboardView.swift          # Main window
│       ├── SettingsView.swift           # Preferences
│       ├── LoginView.swift              # Sign-in window
│       └── Components.swift             # Shared UI pieces
├── macOSWidget/
│   └── AIUsageWidget.swift          # Desktop widget (small / medium / large)
├── macOSTests/                     # macOS unit tests (hosted in the app, Cmd+U)
│                                   #   parsers with on-disk fixtures, demo data, store logic
├── iOS/                            # iPhone/iPad companion app (plan limits & balance)
│   ├── AIUsageiOSApp.swift              # App entry point + provider list UI
│   ├── UsageStoreiOS.swift              # Network-only store + widget snapshot
│   ├── AuthCoordinator.swift            # OAuth via ASWebAuthenticationSession
│   ├── WatchSync.swift                  # Hands snapshot + credentials to the watch (WCSession)
│   └── Assets.xcassets                  # iOS app icon
├── iOSWidget/
│   └── AIUsageiOSWidget.swift       # Home Screen widget (small / medium / large)
├── iOSTests/                       # iOS unit tests (hosted in the app, Cmd+U)
├── watchOS/
│   └── AIUsageWatchApp.swift        # Watch app: self-fetching store + provider list
├── watchOSWidget/
│   └── AIUsageWatchWidget.swift     # Rings complication (accessoryCircular)
└── Signing/
    ├── App.entitlements                 # App Group entitlement (macOS app)
    ├── Widget.entitlements              # App Group + sandbox (macOS widget)
    ├── iOSApp.entitlements              # App Group entitlement (iOS app)
    ├── iOSWidget.entitlements           # App Group entitlement (iOS widget)
    ├── WatchApp.entitlements            # App Group entitlement (watch app)
    └── WatchWidget.entitlements         # App Group entitlement (watch widget)
```

## Notes

- The Anthropic, OpenAI and DeepSeek endpoints are not all officially documented and may change without notice.
- This project is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, OpenCode or DeepSeek. All product names and trademarks belong to their respective owners.

## License

[MIT](LICENSE)
