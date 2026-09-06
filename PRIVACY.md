# Privacy Policy

**AI Usage** — last updated 6 September 2026.

## The short version

AI Usage does not collect, store or transmit any personal data. There is no
account to create, no server of ours to talk to, no analytics and no
telemetry. Everything the app knows stays on your device.

## What the app does with your data

**Your credentials.** To read your quota, the app needs to authenticate as
you. Sign-in uses each provider's own public OAuth flow (the same one their
official command line tools use) or, for DeepSeek, an API key you paste in.
Those credentials are stored on your device only:

- **iOS and watchOS** — in the system Keychain, shared with the app's widget
  and complication so they can refresh on their own.
- **macOS** — in a file readable only by your user account, inside the app's
  App Group container, so the desktop widget can refresh while the app is
  closed.

They are never sent anywhere except to the provider they belong to. Signing
out deletes them.

Each device holds its own session: when you connect the Apple Watch, the
iPhone obtains a separate authorization for it, hands it over once over the
encrypted link between your paired devices, and discards its own copy.

**Your usage figures.** The app asks each provider you have connected for
your own plan limits and balance, using your own session:

| Provider | Endpoint |
|---|---|
| Claude (Anthropic) | `api.anthropic.com`, `console.anthropic.com` |
| OpenAI | `chatgpt.com`, `auth.openai.com` |
| DeepSeek | `api.deepseek.com` |

It also reads the public status pages of Anthropic and OpenAI
(`status.anthropic.com`, `status.openai.com`) to show whether the platform is
having an incident. Those requests carry no credentials and no identifier.

The answers are kept on your device so the widgets can render them, and are
never forwarded anywhere.

**Your local logs (macOS only).** On the Mac, token counts and cost estimates
are computed by reading files the AI command line tools already write on your
own computer: `~/.claude/projects/`, `~/.codex/sessions/` and OpenCode's local
database. They are read, never copied off the machine, and never uploaded.
The iOS and watchOS apps have no such logs and do not read any of your files.

## What the app does not do

- No analytics, crash reporting, advertising or tracking of any kind.
- No data is shared with third parties. The app has no third-party SDKs.
- Nothing is sent to the developer. There is no backend.
- Your prompts and conversations are never read: the app only ever looks at
  usage metadata (token counts, timestamps, model names, cost).

## Children

The app is not directed at children and collects no data from anyone,
including children.

## Changes

Any change to this policy will be published in this file, with the date above
updated.

## Contact

Questions or concerns: <https://github.com/aitorsola/AI-Usage/issues>

---

AI Usage is not affiliated with, endorsed by or sponsored by Anthropic,
OpenAI, OpenCode or DeepSeek. All product names and trademarks belong to their
respective owners.
