# Notchwatch - Claude Code Project Memory

## Project Overview
Notchwatch is a macOS menu bar app that displays Claude Code session state in the Mac's notch area. It reads Claude Code transcripts (and, optionally, hook events) and displays tool usage, token counts, and session status.

It is a fork of `AppGram/agentnotch`, narrowed on purpose. Removed from upstream and not to be brought back: OpenAI Codex support and the OTLP telemetry receiver it needed, the MCP/JSON-RPC process manager behind the old `AppMode` switch, a "meme video" setting whose default URL carried a third party's IP and signed tokens, and a path that put a claude.ai `sessionKey` in the Keychain to call private endpoints while spoofing a browser. That last one is why the no-network property is load-bearing rather than incidental.

**The app makes no network requests, and that claim is in the README.** Keep it true: no `URLSession`, no `import Network`, no sockets, no remote `Data(contentsOf:)`. `Notchwatch.entitlements` is empty and there is no ATS block in `Resources/Info.plist.in`. Adding any of these means editing the README in the same commit.

## Build System
SwiftPM, not Xcode: `Package.swift` declares one executable target and no dependencies, so the whole project builds with `swift build` under the Command Line Tools. There is no `.xcodeproj` — Xcode, when present, opens `Package.swift` directly.

SwiftPM cannot emit a `.app`, so `scripts/build-app.sh` assembles the bundle around the executable: `Resources/Info.plist.in` is the Info.plist template and `scripts/product.env` holds the product name, bundle id, minimum OS and copyright. Both CI and the release pipeline run that same script. Task entry points are in `mise.toml`: `build`, `build:release`, `lint` (= `lint:swift` + `lint:format`), `lint:repo`, `fmt`, `bundle`, `dmg`, `ci`. `mise run test` exists but `Package.swift` declares no test target yet.

Lint has one policy, not two: the pre-commit hook and the CI lint job both run `mise run lint` over the **whole tree**, check-only. The hook does not rewrite files — `mise run fmt` does. `lint:repo` is the non-Swift half (shellcheck, gitleaks, YAML/JSON) and runs `pre-commit run --all-files`; it must never become a dependency of `lint`, because pre-commit calls `mise run lint` and the two would recurse.

Two vendored files are excluded from both Swift tools — `Sources/Notchwatch/Window/CGSSpace.swift` and `Sources/Notchwatch/Views/Notch/NotchShape.swift` (see Licensing). They stay diffable against their upstreams rather than conformed to house style, so `.swiftlint.yml`'s `excluded:` and `.swiftformat`'s `--exclude` must be kept in step with each other and with the paths in `LICENSE`.

The name the UI shows is not a literal anywhere in `Sources/`: `AppIdentity.displayName` reads `CFBundleName`, which `build-app.sh` substitutes from `PRODUCT_NAME`. `COPYRIGHT` in the same file becomes `NSHumanReadableCopyright` and has to name exactly the holders and years that LICENSE does — it is the one copyright string the product ships.

SwiftUI `#Preview` blocks are deliberately absent: the macro lives in a plugin that ships with Xcode.app, so a preview in the sources breaks a Command Line Tools build. Do not reintroduce them.

## Licensing — read before moving or editing these files
The tree is three licences deep, and `LICENSE` is the authority. Two files are
vendored and cannot be relicensed by editing them:

- `Sources/Notchwatch/Window/CGSSpace.swift` — MPL-2.0, from avaidyam/Parrot.
  File-level copyleft: modifications stay MPL-2.0.
- `Sources/Notchwatch/Views/Notch/NotchShape.swift` — MIT, © 2025 Kai Azim, from
  MrKai77/DynamicNotchKit.

Both carry a `// Source: …` header. Keep it, and if either file moves, update its
path in `LICENSE` and `CONTRIBUTING.md` in the same commit — a copyleft clause
naming a path that does not exist attaches to nothing.

Everything inherited from the upstream fork parent is MIT held by the AgentNotch
authors. Upstream ships **no licence file**: the grant is one line in its README.
`LICENSE` says exactly that and does not claim to reproduce an upstream file. Do
not invent copyright holders — no name appears in `LICENSE` that is not verifiable
from a repository (`git log 4139d6f` for the inherited history, DynamicNotchKit's
own `LICENSE` for Kai Azim).

## Key Directories
```
Sources/Notchwatch/
├── Core/
│   ├── ClaudeCode/
│   │   ├── ClaudeCodeManager.swift    # Session discovery, transcript + hook parsing, folded state
│   │   ├── ClaudeContextTracker.swift # Which usage entry counts as the context reading
│   │   ├── ClaudeModelPin.swift       # `model` key of the settings files (1M opt-in)
│   │   ├── GitBranchResolver.swift    # Branch from the session cwd's .git/HEAD
│   │   └── TranscriptTail.swift       # Incremental, line-boundary-safe transcript reads
│   ├── Hooks/                         # Hook bridge: HookEvent, HookInstaller, HookRelay,
│   │                                  #   HookSpool, HookSpoolWatcher (see docs/hooks.md)
│   ├── Coordinators/
│   │   └── UICoordinator.swift        # Notch panel + menu bar lifecycle, geometry updates
│   ├── PowerStateMonitor.swift        # Charging state, for the battery-saver frame rate
│   └── Settings/
│       └── AppSettings.swift          # @AppStorage settings
├── Models/
│   ├── ClaudeCodeModels.swift         # ClaudeSession, ClaudeCodeState, ClaudeTokenUsage,
│   │                                  #   ClaudeContextWindow
│   ├── NotchGeometry.swift            # Cut-out geometry read back from the display
│   ├── NotchSizing.swift              # Display-independent sizing constants
│   └── NotchViewModel.swift           # NotchState (closed/open/peeking) + animations
├── Views/
│   ├── Notch/
│   │   ├── NotchContentView.swift     # Main notch UI, footer, context bar
│   │   ├── NotchGlowBorder.swift      # Animated border glow
│   │   └── NotchShape.swift           # Vendored — MIT, see Licensing above
│   ├── ClaudeCode/                    # ClaudeToolListView, TodoListView,
│   │                                  #   SessionDotsIndicator, PermissionNeededIndicator
│   ├── MenuBar/MenuBarContentView.swift
│   └── Settings/SettingsView.swift    # Settings UI (GeneralSettingsTab)
├── Window/
│   ├── CGSSpace.swift                 # Vendored — MPL-2.0, see Licensing above
│   ├── MenuBarController.swift        # NSStatusItem + popover
│   ├── NotchPanel.swift               # Borderless non-activating panel
│   └── NotchSpaceManager.swift        # Puts the panel in the CGSSpace
├── NotchwatchApp.swift                # @main; AppIdentity.displayName lives here
├── NotchwatchAppDelegate.swift        # Accessory lifecycle, settings window
├── Assets.xcassets/                   # Icon source art; excluded from the target
└── Resources/AppIcon.icns             # What build-app.sh copies into the bundle
```

## Two Data Sources
The transcript is the **data plane** and hooks are the **control plane**; the app
works with the transcript alone and gets timeliness from hooks when they are
registered. `watched[key].isHookDriven` flips once a hook payload arrives for a
session, and from then on the transcript's control-plane fields are ignored for
it (`applyTranscriptControlPlane` is skipped) so the two sources cannot fight.
Token usage and the model id come from the transcript either way — no hook
reports them. Hook wiring, guarantees and the settings-file contract:
[docs/hooks.md](docs/hooks.md).

## Claude Code JSONL Integration

### File Locations
- Claude directory: `~/.claude/`
- IDE sessions: `~/.claude/ide/*.lock`
- Project JSONL: `~/.claude/projects/{project-key}/{uuid}.jsonl`
- Stats cache: `~/.claude/stats-cache.json`
- Hook spool: `~/Library/Application Support/{bundle-id}/hook-events/`

### Project Key Format
Path `/Users/foo/project` becomes `-Users-foo-project` (replace `/` with `-`)

### JSONL Message Types
- `tool_use` - Tool execution started (has id, name, input)
- `tool_result` - Tool completed (has tool_use_id)
- `thinking` - Model thinking block
- `text` - Text output (check for `[Request interrupted by user`)
- `toolUseResult` - Top-level field for tool results
- `system` / `compact_boundary` - Context compaction; carries `compactMetadata`

### Key State Detection
- **Thinking**: `content[].type == "thinking"`, or an assistant message with no
  tool call resolving it
- **Tool running**: Active tools in `state.activeTools`
- **Session done**: `lastStopReason == "end_turn"` with nothing thinking and no
  active tool (`ClaudeCodeState.isSessionComplete`), or interrupted text
- **Permission needed**: tool running ≥ `permissionCheckDelay` (5s) without a result
- **Idle timeout**: no new tool for `toolIdleDelay` (10s)

## Debug Logging
All print statements wrapped in `debugLog()` - only active in DEBUG builds:
```swift
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
```

## Settings (AppSettings.swift)
Every key, in file order. `@AppStorage` writes to `UserDefaults.standard`, whose
domain is the bundle id at run time — changing `BUNDLE_ID` orphans all of it.
```swift
// General
recentToolCallsLimit: Int = 10
showMenuBarItem: Bool = false
showNotchTokenCount: Bool = true
showNotchTokenBreakdown: Bool = true
batterySaverEnabled: Bool = true    // 15 FPS on battery, 25 FPS charging

// Claude Code
enableClaudeCodeJSONL: Bool = true
enableHookBridge: Bool = false      // off until hooks are actually registered
showSessionDots: Bool = true
showPermissionIndicator: Bool = true
showTodoList: Bool = true
showThinkingState: Bool = true

noticeDurationSeconds: Double = 9   // how long a peek notice stays up

// Context & Display
contextTokenLimitOverride: Int = 0  // 0 = derive the window from the model
showContextProgress: Bool = true
toolDisplayMode: String = "list"    // "list" or "singular"
```
`contextTokenLimitOverride` is deliberately a new key. The retired
`contextTokenLimit` defaulted to 200k, so reusing the name would turn every
existing install's stale default into a permanent override of the auto-detected
window. `effectiveContextLimit(for:)` takes a `ClaudeCodeState`, not a model
string — it needs the session's 1M opt-in and peak prompt too.

## Token Usage Structure
```swift
struct ClaudeTokenUsage {
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadInputTokens: Int      // Green in UI - savings
    var cacheCreationInputTokens: Int  // Yellow in UI - creation

    // The three input fields partition one prompt, so only their sum measures
    // the context. `output` is excluded: it is not in the window during the
    // request that produced it, and the next request folds it into that
    // request's prefix.
    var promptTokens: Int { inputTokens + cacheReadInputTokens + cacheCreationInputTokens }
}
```

There is deliberately no price readout. An honest one has to accumulate over
every request of a session, and the app attaches to a transcript at a 2 MB tail —
it never sees what came before.

## Context Reading (ClaudeContextTracker.swift)
The raw sequence of `usage` blocks is not monotonic, and three of the four causes
are artefacts rather than a context that shrank. Measured over 44 local
transcripts (26,750 usage-bearing lines, 11,362 distinct requests): repeated
lines — one per content block, all carrying the same `usage` — account for 15,378
of them; `<synthetic>` entries carry an all-zero block; a handful of entries are
appended again verbatim thousands of lines later. Only `compact_boundary` is a
real reset. With the first three filtered and the last honoured, the sequence is
monotonic within every compaction segment, so the tracker takes the newest
accepted request and refuses any other decrease.

## Context Window (ClaudeContextWindow.resolve)
Claude Code's 1M opt-in **never reaches `message.model`** — across the same 44
transcripts that field is only ever a bare id. The suffix lives on the model
*pin* (`~/.claude/settings.json` → `"model": "opus[1m]"`) and on
`toolUseResult.resolvedModel` of a `Task` result, and neither is complete, so the
window is floored by the largest prompt the session actually sent: a window
cannot be smaller than a prompt that fit in it.

## UI Components

### Notch States
- `closed` - Minimal view with wings showing tool/thinking status
- `peeking` - Dropdown notification (permission request)
- `open` - Full expanded view with tools list, todos, footer

### Glow Colors
- Activity: orange, `rgb(0.9, 0.4, 0.1)` with `rgb(1.0, 0.55, 0.2)` as the bright pass
- Startup: light blue, `rgb(0.55, 0.8, 0.9)` / `rgb(0.75, 0.9, 1.0)`

### Footer Display
- Session duration
- Git branch badge (purple)
- Token total (sparkles icon)
- Cache read tokens (green arrow down)
- Cache write tokens (yellow arrow up)

### Context Progress Bar
- `promptTokens` against `AppSettings.effectiveContextLimit(for:)`
- Colors: green (≤50%), yellow (>50%), orange (>70%), red (>90%)

## Panel Control and the Demo Fixture
`--panel open|close|toggle|peek|demo-on|demo-off` talks to a running instance over
a distributed notification (`PanelControl`). The sender turns its run loop briefly
before exiting — the post goes to the system broker over XPC and is lost if the
process dies first, which is how the first version failed silently.

Demo mode swaps every reading for `DemoScenario`'s fixture and **stops the
watchers**, rather than letting them run and be ignored: a scan landing between a
command and a screenshot would overwrite the fixture. `scanForSessions` returns
early while it is on. Screenshots for documentation are taken this way and never
from real sessions — the panel displays the user's own work, so a real capture is
a capture of private activity.

## Release Process
Fully automated; nothing is built or tagged by hand. release-please (`release-type: simple`) reads Conventional Commits, opens a release PR, and merging it tags the version and calls `.github/workflows/release.yml`, which runs `mise run bundle` (i.e. `scripts/build-app.sh`), `scripts/create-dmg.sh` and `scripts/verify-dmg.sh`, then uploads the `.dmg` to the GitHub Release. Never hand-edit `CHANGELOG.md`, `version.txt`, `.release-please-manifest.json`, or the tags.

Everything publishes to **this** repository's Releases — `sanchpet/notchwatch`. Nothing is pushed upstream, and there is no Homebrew tap or cask: a cask installs with quarantine set, so it only becomes worth having once builds are signed. Do not add one before then.

Signing is optional: without the five Developer ID secrets the pipeline still produces an image, named `<Product>-<version>-unsigned.dmg`, and prepends an "Unsigned build" note to the release body. Nothing has been released yet — `version.txt` and the manifest are both at `0.0.0`.

Step order in the publish step is a safety property, not a preference: **the note goes into the release body before the asset is uploaded, and the asset is uploaded last.** Uploading first leaves an unsigned, unmarked disk image publicly downloadable for as long as the edit takes — and forever if the edit fails, since the step runs under `set -e`. When the job creates the release itself (a hand-dispatched tag), it creates a draft and flips it to published as the final act; a release that release-please already published cannot be un-published, which is why the ordering has to hold on its own. The banner is guarded by an HTML-comment marker so a re-run does not stack it.

## Important Patterns

### Session Watching
- Uses `DispatchSource.makeFileSystemObjectSource` with `O_EVTONLY`
- Watches for `.write, .extend` events
- Fallback scan if direct projectKey match fails

### State Synchronization
`sessionStates[sessionKey]` is the only per-session truth; the published `state`
is computed by folding it. There is **no** `selectedSession` — upstream had one
and only ever assigned it when exactly one session existed, so with an editor
holding an IDE lock next to a terminal session nothing was ever selected and the
UI showed a default-constructed state. Do not reintroduce a selection.

- Single-valued readouts (model, tokens, branch, todos) come from
  `focusedSessionKey`: active first, then most recently updated.
- `activeTools` / `recentTools` are folded across every session, newest first,
  deduplicated by tool id.
- `needsPermission` outranks the focus: a prompt waiting anywhere wins.
- `state` is computed, so mutating `sessionStates` needs an explicit
  `objectWillChange.send()` for the UI to update.

### Interruption Detection
Check multiple locations:
1. `toolUseResult` field containing "interrupted"
2. `text` content containing `[Request interrupted by user`
3. `tool_result` with "rejected" content

### Timers
- `idleCheckTimer` — one-shot, `idleCheckDelay` 3s, marks thinking as false
- `toolIdleTimer` — one-shot, `toolIdleDelay` 10s, marks the session done if no new tools
- `permissionCheckTimer` — repeating, `permissionCheckDelay` 5s; a tool that has
  been running at least that long with no result is treated as awaiting permission
- `sessionScanTimer` — repeating, 10s, rescans for sessions
