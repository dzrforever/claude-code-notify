#!/bin/bash
# Claude Code notification hook with focus-aware delayed debounce.
# Claude Code 通知 hook（基于窗口焦点的延迟去抖）
#
# Fires on the Notification event (matcher: permission_prompt|idle_prompt).
# When Claude blocks (asks permission / idle), it polls the frontmost app for
# DELAY seconds:
#   - If the terminal app that triggered it is focused at ANY point → you're
#     present → stay silent.
#   - If that terminal app NEVER comes to the foreground during DELAY → you've
#     walked away → send a notification (macOS banner + ntfy push to phone/watch).
#
# So you only get pinged when you've actually left the terminal — not while
# you're sitting there deciding whether to approve something.
#
# Fail-open: every external command is guarded; the script always exits 0 so a
# failure here can never block Claude.

# ── Config ─────────────────────────────────────────────
# Optional: put overrides in ~/.claude/hooks/notify.conf (kept out of git):
#   NTFY_TOPIC="your-unique-topic"
#   DELAY=30
CONF="$(dirname "$0")/notify.conf"
[ -f "$CONF" ] && . "$CONF"

DELAY="${DELAY:-30}"                          # seconds without terminal focus before alerting
POLL_INTERVAL="${POLL_INTERVAL:-3}"           # focus poll interval (seconds)
NTFY_TOPIC="${NTFY_TOPIC:-YOUR_NTFY_TOPIC}"   # subscribe to this topic in the ntfy app
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
FALLBACK_APP="${FALLBACK_APP:-com.apple.Terminal}"  # fallback if frontmost app detection fails
TN="${TN:-/opt/homebrew/bin/terminal-notifier}"

# ── Read & parse hook JSON (stdin) ─────────────────────
INPUT="$(cat)"
NTYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // "generic"' 2>/dev/null)"
MSG="$(printf '%s' "$INPUT"   | jq -r '.message // "Claude Code"'        2>/dev/null)"
CWD="$(printf '%s' "$INPUT"   | jq -r '.cwd // ""'                       2>/dev/null)"
PROJECT="$(basename "$CWD" 2>/dev/null)"
[ -z "$PROJECT" ] && PROJECT="Claude Code"

# ── Capture the foreground app at trigger time as the "target terminal" ──
# When Claude blocks, the frontmost app is almost certainly the terminal you're
# running Claude in.
front_app() { osascript -e 'id of app (path to frontmost application as text)' 2>/dev/null; }
TARGET_APP="$(front_app)"
[ -z "$TARGET_APP" ] && TARGET_APP="$FALLBACK_APP"

# ── Title / priority per notification type ─────────────
case "$NTYPE" in
  permission_prompt)
    TITLE="⚠️ Claude needs your approval"
    NTFY_PRIORITY="high"
    NTFY_TAGS="warning"
    SOUND="Glass"
    ;;
  idle_prompt)
    TITLE="✅ Claude is done"
    NTFY_PRIORITY="default"
    NTFY_TAGS="white_check_mark"
    SOUND="Ping"
    ;;
  *)
    TITLE="🔔 Claude Code"
    NTFY_PRIORITY="default"
    NTFY_TAGS="bell"
    SOUND="Ping"
    ;;
esac

# ── Background: poll focus for DELAY; cancel if terminal gets focus, else notify ──
(
  ELAPSED=0
  while [ "$ELAPSED" -lt "$DELAY" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    # Target terminal is foreground → you're present → cancel silently.
    if [ "$(front_app)" = "$TARGET_APP" ]; then
      exit 0
    fi
  done

  # Terminal never regained focus during DELAY — you've walked away, so alert.
  if [ -x "$TN" ]; then
    "$TN" \
      -title "$TITLE" \
      -subtitle "$PROJECT" \
      -message "$MSG" \
      -sound "$SOUND" \
      -activate "$TARGET_APP" \
      -group "claude-code-notify" >/dev/null 2>&1 || true
  fi

  curl -s --max-time 5 \
    -H "Title: $TITLE — $PROJECT" \
    -H "Priority: $NTFY_PRIORITY" \
    -H "Tags: $NTFY_TAGS" \
    -d "$MSG" \
    "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1 || true
) >/dev/null 2>&1 &

# Return immediately so Claude is never blocked.
exit 0
