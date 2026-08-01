# Claude Code hooks

The app reads session state from two places. Hooks are the **control plane** —
which tool started, where, in which session, at the moment it happened. The
transcript (`~/.claude/projects/**/*.jsonl`) is the **data plane**: token usage
and the model id, which no hook reports.

Hooks are optional. Without them the transcript drives everything, which is what
the app did before — less timely, and dependent on a file format Claude Code
does not promise to keep.

## What gets registered

Settings → *Claude Code Hooks* → **Register…** adds seven entries to
`~/.claude/settings.json`, one per event:

| Event | What it tells the app |
|---|---|
| `SessionStart` | a session exists, in this directory, with this transcript |
| `UserPromptSubmit` | the agent is working again |
| `PreToolUse` | a tool started (name and input) |
| `PostToolUse` | that tool returned |
| `Notification` | Claude is asking for permission |
| `Stop` | the turn is over |
| `SessionEnd` | the session is gone |

Each entry runs the app's own binary in relay mode:

```json
{ "type": "command", "command": "\"/Applications/<App>.app/Contents/MacOS/<App>\" --hook-relay", "timeout": 5 }
```

Nothing is written without pressing that button and confirming the dialog that
names the file. The previous `settings.json` is copied to
`settings.json.notchwatch-<timestamp>.bak` first, unrelated keys are preserved,
and **Remove** deletes exactly the entries carrying `--hook-relay` — hooks you
wrote yourself are not touched.

To undo it by hand, delete those entries from `~/.claude/settings.json`.

## How an event reaches the app

`--hook-relay` reads the payload from stdin, writes it into
`~/Library/Application Support/<bundle-id>/hook-events/`, and exits. The app
watches that directory, consumes each file and deletes it.

Two properties matter, both because of what a hook is allowed to cost:

- **Fail open.** `PreToolUse` runs *before* the tool it describes, so a hook that
  hangs or errors is felt by the user as their agent breaking. Every path in the
  relay ends in `exit(0)`, a watchdog caps the whole run at two seconds, and the
  app not running is not an error — the file simply waits, and anything older
  than five minutes is discarded unread.
- **Atomic publish.** Each event is staged and then `rename`d into place, so a
  reader sees a whole payload or none. Appending to a shared log would not do:
  a `Write` tool's input is far past `PIPE_BUF`, and concurrent sessions would
  interleave mid-payload.

Payloads over 4 MB are dropped rather than buffered. Losing one event costs a
stale display for a moment; delaying the tool costs the user their session.

## Drift

Every field except the event name is optional at decode time, and an unknown
`hook_event_name` is ignored rather than rejected. Pre/post pairing uses
`tool_use_id` when the payload carries it and falls back to the most recent
running tool of the same name when it does not.
