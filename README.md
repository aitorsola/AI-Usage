<p align="center">
 <img src="https://github.com/user-attachments/assets/864bf8c1-37ef-4564-a67d-138bfcc37fbe" height="360" alt="Menu bar panel">
  &nbsp;&nbsp;
 <img src="https://github.com/user-attachments/assets/ffab120f-0451-449e-91d1-4329d1aa8544" height="360" alt="Desktop widget — three sizes">
</p>

<p align="center">
 <img src="https://github.com/user-attachments/assets/b276963b-efcb-4aee-8e28-762f389e532f" width="680" alt="Dashboard window">
</p>

# AI Usage

A native macOS menu bar app — with a desktop widget — to keep an eye on your AI assistant usage — **Claude**, **OpenAI**, **OpenCode** and **DeepSeek** — without leaving the keyboard: plan limits at a glance, token counts, cost and prepaid balance.

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
- **Desktop widget** — a WidgetKit widget that mirrors the panel on your desktop or Notification Center, in three sizes: *small* shows your primary provider's session and weekly gauges with reset countdowns; *medium* keeps the first provider with today's cost and tokens; *large* mirrors the whole panel — every enabled provider plus the 7-day chart (shown only when the weekly section is on). App and widget share a ready-to-render snapshot through an App Group.
- **Plan extras, only when they exist** — Claude extra usage (monthly overage in dollars), OpenAI credits balance, individual spend limits, DeepSeek balance, and a red banner with the reason whenever a limit is hit. Empty data never renders empty UI.
- **Three ways to connect**
  - **Browser OAuth** (Claude, OpenAI) — OAuth 2.0 + PKCE with a local callback server, the same public flows used by Claude Code (port 54545) and Codex CLI (port 1455). The app never reads other apps' credentials, so macOS never shows keychain permission prompts.
  - **API key** (DeepSeek) — pasted in Settings and stored in the app's own Keychain item; only used to read your balance. Invalid keys are detected and flagged.
  - **No sign-in** (OpenCode) — usage is read straight from the local database.
- **Menu customization** — sections (Claude / OpenAI / OpenCode / DeepSeek / last 7 days) can be hidden and reordered. Sections with no data or session stay hidden automatically. Right-click the menu bar icon for a quick context menu (open, refresh, settings, quit).
- **Localized** — Spanish, English, French, German, Italian, Portuguese, Japanese, Simplified Chinese, Korean and Russian. Follows the system language.
- **Launch at login**, automatic refresh every 60 seconds, incremental file parsing (only re-reads changed session files).

## Requirements

- macOS 14 or later (Apple Silicon and Intel).
- Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the build generates an Xcode project that bundles the app together with its widget extension.

## Build from source

```sh
brew install xcodegen   # once
./build_xcode.sh
open "/Applications/AI Usage.app"
```

`build_xcode.sh` generates the icon asset catalog, runs XcodeGen to produce `AIUsage.xcodeproj` from `project.yml`, builds the app and the widget extension, signs both bundles manually and installs `AI Usage.app` into `/Applications`. Signing picks, in order: the `CODESIGN_IDENTITY` environment variable, the first *Apple Development* identity in your keychain, or an ad-hoc signature. A stable identity is recommended so Keychain approvals survive rebuilds. The app and widget share data through the `group.dev.aitor.ai-usage` App Group, so both targets are signed with matching entitlements from `Signing/`.

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

### Authentication

Claude and OpenAI use their public OAuth clients with the standard PKCE flow. Sign-in opens the browser; the authorization redirects back to a loopback server bound to the same port each CLI uses. Access/refresh tokens are stored under dedicated Keychain items (`AI Usage-credentials`, `AI Usage-openai-credentials`) and refreshed transparently before expiry. Signing out deletes the item. For OpenAI, if a plaintext `~/.codex/auth.json` exists (older Codex CLI versions), it is used as a fallback session.

DeepSeek uses a personal API key (from `platform.deepseek.com`) stored in its own Keychain item (`AI Usage-deepseek-key`); it is only ever sent to DeepSeek to read your balance.

OpenCode requires no authentication — its usage lives in a local SQLite database, opened read-only.

### Privacy

Everything runs locally. The only network requests are the usage/profile/balance calls to Anthropic, OpenAI and DeepSeek described above, authenticated with your own session or key. No analytics, no telemetry, no third-party services.

## Project layout

```
├── project.yml             # XcodeGen spec (app + widget targets)
├── build_xcode.sh          # Generate project, build, sign, install
├── Sources/AIUsage/        # Menu bar app
│   ├── AIUsageApp.swift        # App entry point, scenes
│   ├── UsageStore.swift        # Refresh loop, provider state, widget snapshot
│   ├── UsageParser.swift       # Claude Code transcript parsing + aggregation
│   ├── CodexParser.swift       # Codex CLI session parsing, rate-limit schema
│   ├── OpenCodeParser.swift    # OpenCode SQLite database reader
│   ├── PlanFetcher.swift       # Anthropic usage/profile endpoints
│   ├── OpenAIAuth.swift        # OpenAI OAuth, token store, usage endpoint
│   ├── AnthropicAuth.swift     # Anthropic OAuth, loopback callback server
│   ├── DeepSeekAuth.swift      # DeepSeek API key store + balance endpoint
│   ├── Pricing.swift           # Per-model price tables
│   ├── Localization.swift      # Language detection + translation catalog
│   ├── MenuContentView.swift   # Menu bar dropdown + status label
│   ├── DashboardView.swift     # Main window
│   ├── SettingsView.swift      # Preferences
│   ├── LoginView.swift         # Sign-in window
│   ├── Components.swift        # Shared UI pieces
│   └── StatusItemMenu.swift    # Right-click context menu
├── WidgetExtension/
│   └── AIUsageWidget.swift  # WidgetKit widget (small / medium / large)
├── Shared/
│   └── WidgetShared.swift   # App-Group snapshot model, shared by both targets
└── Signing/
    ├── App.entitlements     # App Group entitlement (main app)
    └── Widget.entitlements  # App Group + sandbox (widget extension)
```

## Notes

- The Anthropic, OpenAI and DeepSeek endpoints are not all officially documented and may change without notice.
- This project is not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, OpenCode or DeepSeek. All product names and trademarks belong to their respective owners.

## License

[MIT](LICENSE)
