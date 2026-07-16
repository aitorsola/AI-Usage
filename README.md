# AI Usage

A native macOS menu bar app to keep an eye on your AI assistant usage — **Claude** and **OpenAI** — without leaving the keyboard: plan limits at a glance, token counts, and estimated cost.

## Features

- **Menu bar at a glance** — remaining percentage of your session and weekly limits (e.g. `✳ 63% · 87%`). Configurable: remaining vs. used, and which provider drives the number (or today's total cost).
- **Two providers, one panel**
  - **Claude** — token usage and cost parsed from local Claude Code transcripts; live plan limits (5-hour session, weekly, per-model) from Anthropic's usage endpoint.
  - **OpenAI** — token usage from local Codex CLI sessions; live rate limits, plan, credits and spend caps from the ChatGPT backend.
- **Dashboard window** — per-provider tabs with today / current block / 7-day / 30-day cards, plan limit gauges, daily history bars and a per-model breakdown.
- **Plan extras, only when they exist** — Claude extra usage (monthly overage in dollars), OpenAI credits balance, individual spend limits, and a red banner with the reason whenever a limit is hit. Empty data never renders empty UI.
- **Browser sign-in** — OAuth 2.0 + PKCE with a local callback server, the same public flows used by Claude Code (port 54545) and Codex CLI (port 1455). Tokens are stored in the app's own Keychain items and refreshed automatically. The app never reads other apps' credentials, so macOS never shows keychain permission prompts.
- **Menu customization** — sections (Claude / OpenAI / last 7 days) can be hidden and reordered. Right-click the menu bar icon for a quick context menu (open, refresh, settings, quit).
- **Localized** — Spanish, English, French, German, Italian, Portuguese, Japanese, Simplified Chinese, Korean and Russian. Follows the system language.
- **Launch at login**, automatic refresh every 60 seconds, incremental file parsing (only re-reads changed session files).

## Requirements

- macOS 14 or later (Apple Silicon and Intel).
- To build: Xcode 15+ command line tools.

## Build & install

```sh
./build.sh
open "/Applications/AI Usage.app"
```

The script compiles a release build, packages `AI Usage.app` into `/Applications`, generates the icon and signs the bundle. Signing picks, in order: the `CODESIGN_IDENTITY` environment variable, the first *Apple Development* identity in your keychain, or an ad-hoc signature. A stable identity is recommended so Keychain approvals survive rebuilds.

To build a universal binary for distribution:

```sh
swift build -c release --arch arm64 --arch x86_64
```

## How it works

### Data sources

| | Tokens & cost | Plan limits |
|---|---|---|
| **Claude** | `~/.claude/projects/**/*.jsonl` (Claude Code transcripts) | `api.anthropic.com/api/oauth/usage` + `/api/oauth/profile` |
| **OpenAI** | `~/.codex/sessions/**/*.jsonl` (Codex CLI sessions) | `chatgpt.com/backend-api/wham/usage` |

- Cost figures are **API-equivalent estimates** computed from per-model pricing (including cache write/read multipliers for Claude and cached-input pricing for OpenAI). Subscription plans don't bill per token — treat the number as a consumption gauge.
- Plan limits come exclusively from the provider endpoints, using your own session. Duplicate transcript entries are deduplicated by message and request id.

### Authentication

Both providers use their public OAuth clients with the standard PKCE flow. Sign-in opens the browser; the authorization redirects back to a loopback server bound to the same port each CLI uses. Access/refresh tokens are stored under dedicated Keychain items (`AI Usage-credentials`, `AI Usage-openai-credentials`) and refreshed transparently before expiry. Signing out deletes the item.

For OpenAI, if a plaintext `~/.codex/auth.json` exists (older Codex CLI versions), it is used as a fallback session.

### Privacy

Everything runs locally. The only network requests are the usage/profile calls to Anthropic and OpenAI described above, authenticated with your own session. No analytics, no telemetry, no third-party services.

## Project layout

```
Sources/AIUsage/
├── AIUsageApp.swift    # App entry point, scenes
├── UsageStore.swift        # Refresh loop, provider state
├── UsageParser.swift       # Claude Code transcript parsing + aggregation
├── CodexParser.swift       # Codex CLI session parsing, rate-limit schema
├── PlanFetcher.swift       # Anthropic usage/profile endpoints
├── OpenAIAuth.swift        # OpenAI OAuth, token store, usage endpoint
├── AnthropicAuth.swift     # Anthropic OAuth, loopback callback server
├── Pricing.swift           # Per-model price tables
├── Localization.swift      # Language detection + translation catalog
├── MenuContentView.swift   # Menu bar dropdown
├── DashboardView.swift     # Main window
├── SettingsView.swift      # Preferences
├── LoginView.swift         # Sign-in window
├── Components.swift        # Shared UI pieces
└── StatusItemMenu.swift    # Right-click context menu
```

## Notes

- The usage endpoints are not officially documented and may change without notice.
- This project is not affiliated with, endorsed by, or sponsored by Anthropic or OpenAI. All product names and trademarks belong to their respective owners.

## License

[MIT](LICENSE)
