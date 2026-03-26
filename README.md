# ClaudeMonitor

A native macOS menu bar app for monitoring Claude usage limits (Max subscription).

## Preview

```
● 5h  29%  3ч5м
● 7d  48%  3д5ч
```

The dot color reflects current load:

| Color | Usage |
|-------|-------|
| 🟢 Green | below 60% |
| 🟠 Orange | 60–90% |
| 🔴 Red | 90%+ |

Click the icon to open a menu with details and a manual refresh button.

## Requirements

- macOS 12.0+
- [Claude Code](https://claude.ai/code) installed and signed in
- Xcode Command Line Tools: `xcode-select --install`

## Installation

### From DMG

1. Download `ClaudeMonitor.dmg`
2. Open the DMG → drag `ClaudeMonitor.app` to `/Applications`
3. First launch: right-click → **Open** (to bypass Gatekeeper)
4. The icon will appear in the menu bar

### Build from source

```bash
git clone <repo>
cd ClaudeMonitor
bash build-dmg.sh
```

This produces `ClaudeMonitor.dmg` and `dist/ClaudeMonitor.app`.

## How it works

The app calls the Anthropic API (`/api/oauth/usage`) — the same endpoint Claude Code uses internally — and displays utilization for the current 5-hour window and the 7-day rolling period.

- The auth token is read from the system Keychain, where Claude Code stores it on login — no separate authentication needed
- Responses are cached for 2 minutes (`~/.cache/claude-api-response.json`) to avoid hammering the API
- Rate limit errors trigger exponential backoff (120s → 240s → … → 600s max)
- The UI refreshes every 60 seconds, served from cache

## Uninstalling

```bash
pkill ClaudeMonitor
rm -rf /Applications/ClaudeMonitor.app

# Optional: clear the cache
rm -f ~/.cache/claude-api-response.json \
      ~/.cache/claude-usage-backoff \
      ~/.cache/claude-usage.lock
```

## Project structure

```
ClaudeMonitor/
├── ClaudeMonitor.xcodeproj/      # Xcode project
├── ClaudeMonitor/
│   ├── main.swift                # Entry point
│   ├── AppDelegate.swift         # App delegate
│   ├── StatusBarController.swift # Icon, menu, rendering
│   ├── UsageAPI.swift            # API, cache, Keychain
│   └── Info.plist
└── build-dmg.sh                  # Build & DMG script
```
