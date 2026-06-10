# claude-code-notify

A [Claude Code](https://code.claude.com) notification hook that pings your phone
and Mac **only when you've actually walked away** — not while you're sitting at
the terminal deciding whether to approve something.

When Claude blocks (asks for permission, or finishes and goes idle), this hook
waits a short window and watches whether your terminal window regains focus:

- **You're still at the terminal** (the window gets focus at any point during the
  window) → stays silent. No nagging.
- **You've left** (the terminal never comes back to the foreground for the whole
  window) → sends a macOS banner **and** an [ntfy](https://ntfy.sh) push to your
  phone / Apple Watch.

The notification click jumps back to whichever terminal app triggered it
(Terminal.app, iTerm, an IDE's integrated terminal, etc. — detected dynamically).

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
- [ntfy app](https://ntfy.sh) on your phone (for the push half — optional; the
  Mac banner works without it)

## Install

1. **Copy the hook** somewhere stable, e.g. your Claude hooks dir:

   ```bash
   mkdir -p ~/.claude/hooks
   cp notify.sh ~/.claude/hooks/notify.sh
   chmod +x ~/.claude/hooks/notify.sh
   ```

2. **Configure your ntfy topic.** Copy the example config next to the script and
   set your own unique topic:

   ```bash
   cp notify.conf.example ~/.claude/hooks/notify.conf
   # edit ~/.claude/hooks/notify.conf and set NTFY_TOPIC
   ```

   Pick a long, random topic name — anyone who knows it can push to and read your
   alerts. Then subscribe to the same topic in the ntfy app on your phone.

   (You can also set `NTFY_TOPIC` as an env var instead of using the conf file.)

3. **Register the hook** in `~/.claude/settings.json`:

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

   Use the absolute path to where you put `notify.sh`.

## Configuration

All knobs live in `notify.conf` (or as env vars). Defaults shown:

| Key             | Default                              | Meaning                                                       |
| --------------- | ------------------------------------ | ------------------------------------------------------------- |
| `NTFY_TOPIC`    | `YOUR_NTFY_TOPIC`                    | ntfy topic to push to. **Set this.**                          |
| `DELAY`         | `30`                                 | Seconds the terminal must stay unfocused before alerting.     |
| `POLL_INTERVAL` | `3`                                  | How often (seconds) to check the foreground app.              |
| `NTFY_SERVER`   | `https://ntfy.sh`                    | Override for a self-hosted ntfy server.                       |
| `FALLBACK_APP`  | `com.apple.Terminal`                 | App to focus on click if frontmost detection fails.           |
| `TN`            | `/opt/homebrew/bin/terminal-notifier`| Path to terminal-notifier.                                    |

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
- The target terminal is whatever app is frontmost at the moment Claude blocks.

## License

MIT
