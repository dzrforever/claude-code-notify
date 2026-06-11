# claude-code-notify

A [Claude Code](https://code.claude.com) notification hook that pings your phone
and Mac **only when you've actually walked away** — not while you're sitting at
the terminal deciding whether to approve something. Pushes go through
[Bark](https://bark.day.app) (iOS), with **three distinct categories**, each with
its own icon.

When Claude blocks (asks for permission, asks a question, or finishes and goes
idle), this hook waits a short window and watches whether your terminal window
regains focus:

- **You're still at the terminal** (the window gets focus at any point during the
  window) → stays silent. No nagging.
- **You've left** (the terminal never comes back to the foreground for the whole
  window) → sends a macOS banner **and** a [Bark](https://bark.day.app) push to
  your phone / Apple Watch.

## Three notification categories

Each gets its own title and icon so you can tell at a glance what Claude wants:

| Category       | When                                    | Icon       |
| -------------- | --------------------------------------- | ---------- |
| 🛡️ Approval    | A tool (Bash/Write/…) needs your OK     | shield     |
| ❓ Question     | Claude asks you (AskUserQuestion)       | question   |
| ✅ Done         | Task finished / idle, waiting for you   | check      |

> Note: the `Notification` hook can't see the tool name, so approval vs. question
> is sniffed from the message text; unmatched prompts fall back to "approval".

## How it works

It hooks the Claude Code `Notification` event (`permission_prompt` and
`idle_prompt`). On trigger it records the frontmost app (your terminal), then
polls the foreground for `DELAY` seconds. Focus seen → cancel. Never seen →
notify. Everything runs in the background and the script exits immediately, so
Claude is never blocked.

## Requirements

- macOS
- [Claude Code](https://code.claude.com)
- [`terminal-notifier`](https://github.com/julienXX/terminal-notifier): `brew install terminal-notifier`
- `jq` (preinstalled on recent macOS, or `brew install jq`)
- [Bark app](https://bark.day.app) on your iPhone (for the push half; the Mac
  banner works without it)
- An HTTPS image host for the three category icons (iOS ignores plain-HTTP
  notification icons)

## Install

1. **Copy the hook** into your Claude hooks dir:

   ```bash
   mkdir -p ~/.claude/hooks
   cp notify.sh ~/.claude/hooks/notify.sh
   chmod +x ~/.claude/hooks/notify.sh
   ```

2. **Configure.** Copy the example config next to the script and set your Bark
   key (and optionally your own icon URLs):

   ```bash
   cp notify.conf.example ~/.claude/hooks/notify.conf
   # edit ~/.claude/hooks/notify.conf — set BARK_KEY (from the Bark app)
   ```

   Get `BARK_KEY` from the Bark app: it's the part after `api.day.app/` in the
   URL the app shows you.

3. **Host the icons over HTTPS.** Put `shield.png`/`question.png`/`check.png` (or
   your own) on any HTTPS host and set `ICON_APPROVAL` / `ICON_QUESTION` /
   `ICON_DONE` in `notify.conf`. **HTTP icons are silently dropped by iOS.**

4. **Register the hook** in `~/.claude/settings.json`:

   ```json
   {
     "hooks": {
       "Notification": [
         {
           "matcher": "permission_prompt|idle_prompt",
           "hooks": [
             { "type": "command", "command": "/Users/YOU/.claude/hooks/notify.sh" }
           ]
         }
       ]
     }
   }
   ```

## Configuration

All knobs live in `notify.conf` (or as env vars). Defaults shown:

| Key             | Default                              | Meaning                                                       |
| --------------- | ------------------------------------ | ------------------------------------------------------------- |
| `BARK_KEY`      | `YOUR_BARK_KEY`                      | Bark device key. **Set this.**                                |
| `DELAY`         | `30`                                 | Seconds the terminal must stay unfocused before alerting.     |
| `POLL_INTERVAL` | `3`                                  | How often (seconds) to check the foreground app.              |
| `BARK_SERVER`   | `https://api.day.app`                | Override for a self-hosted Bark server.                       |
| `ICON_APPROVAL` | sample shield URL                    | HTTPS icon for approval pushes.                               |
| `ICON_QUESTION` | sample question URL                  | HTTPS icon for question pushes.                               |
| `ICON_DONE`     | sample check URL                     | HTTPS icon for done pushes.                                   |
| `FALLBACK_APP`  | `com.apple.Terminal`                 | App to focus on click if frontmost detection fails.           |
| `TN`            | `/opt/homebrew/bin/terminal-notifier`| Path to terminal-notifier.                                    |

All three categories use Bark's `timeSensitive` level (shows in Focus mode
without the harsh always-ring behavior of `critical`). Tune per-category level /
sound / volume in the `case` block in `notify.sh`.

## Test it

```bash
echo '{"notification_type":"permission_prompt","message":"test","cwd":"'"$PWD"'"}' \
  | ~/.claude/hooks/notify.sh
# Switch away from your terminal and wait DELAY seconds → banner + push.
# Stay in the terminal → nothing (you're present).
```

## Notes & limitations

- Focus detection is **app-level**, not tab/window-level: if you run multiple
  tabs in the same terminal app, that app being foreground counts as "present".
- Notification icons **must be HTTPS** — iOS drops HTTP ones and shows the
  default Bark icon.
- Approval vs. question is inferred from message text, not a tool name.

## License

MIT
