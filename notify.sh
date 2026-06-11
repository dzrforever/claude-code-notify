#!/bin/bash
# Claude Code notification hook with focus-aware delayed debounce. (Bark push)
# Claude Code 通知 hook（基于窗口焦点的延迟去抖，Bark 推送）
#
# Fires on the Notification event (matcher: permission_prompt|idle_prompt).
# When Claude blocks (asks permission / idle), it polls the frontmost app for
# DELAY seconds:
#   - If the terminal app that triggered it is focused at ANY point → present → silent.
#   - If that terminal app NEVER comes to the foreground during DELAY → you've
#     walked away → send a macOS banner + Bark push to phone/watch.
#
# Fail-open: every external command is guarded; the script always exits 0.

# ── Config ─────────────────────────────────────────────
# Put your real key in ~/.claude/hooks/notify.conf (gitignored):
#   BARK_KEY="your-bark-device-key"
#   DELAY=30
CONF="$(dirname "$0")/notify.conf"
[ -f "$CONF" ] && . "$CONF"

DELAY="${DELAY:-30}"                           # seconds without terminal focus before alerting
POLL_INTERVAL="${POLL_INTERVAL:-3}"            # focus poll interval (seconds)
BARK_KEY="${BARK_KEY:-YOUR_BARK_KEY}"          # Bark device key (from the Bark app)
BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
# Per-category icons (must be HTTPS — iOS ignores plain-HTTP notification icons).
ICON_APPROVAL="${ICON_APPROVAL:-https://p9.qhimg.com/t11b673bcd6f75d2523720b260b.png}"  # shield
ICON_QUESTION="${ICON_QUESTION:-https://p1.qhimg.com/t11b673bcd6b61b1f8c2e71381e.png}"  # question
ICON_DONE="${ICON_DONE:-https://p7.qhimg.com/t11b673bcd6aac0371417bc2e89.png}"          # check
FALLBACK_APP="${FALLBACK_APP:-com.apple.Terminal}"  # fallback if frontmost detection fails
TN="${TN:-/opt/homebrew/bin/terminal-notifier}"

# ── Read & parse hook JSON (stdin) ─────────────────────
INPUT="$(cat)"
NTYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // "generic"' 2>/dev/null)"
MSG="$(printf '%s' "$INPUT"   | jq -r '.message // "Claude Code"'        2>/dev/null)"
CWD="$(printf '%s' "$INPUT"   | jq -r '.cwd // ""'                       2>/dev/null)"
PROJECT="$(basename "$CWD" 2>/dev/null)"
[ -z "$PROJECT" ] && PROJECT="Claude Code"

# ── Capture the foreground app at trigger time as the "target terminal" ──
front_app() { osascript -e 'id of app (path to frontmost application as text)' 2>/dev/null; }
TARGET_APP="$(front_app)"
[ -z "$TARGET_APP" ] && TARGET_APP="$FALLBACK_APP"

# ── Classify into 3 categories, each with its own icon / title / Bark params ──
# Bark levels: critical (rings even on silent), active (default), timeSensitive, passive.
#  1) permission/approval  → shield  (Bash/Write etc. need approval)
#  2) user question        → question (AskUserQuestion multiple-choice)
#  3) done/idle            → check   (task finished, waiting for you)
# permission_prompt covers BOTH approval and AskUserQuestion; the hook can't see
# the tool name, so we sniff the message text for question markers. Unmatched
# permission_prompt falls back to "approval" (safe: both are blocking actions).
if [ "$NTYPE" = "idle_prompt" ]; then
  CATEGORY="done"
elif printf '%s' "$MSG" | grep -qiE 'askuserquestion|"questions"|choose an option|select an option|多选|选择'; then
  CATEGORY="question"
else
  CATEGORY="approval"
fi

case "$CATEGORY" in
  approval)
    TITLE="🛡️ Claude 需要审批"
    ICON="$ICON_APPROVAL"
    SOUND="Glass"
    BARK_LEVEL="timeSensitive"
    BARK_SOUND="bell"
    BARK_CALL="0"
    BARK_VOLUME="5"
    ;;
  question)
    TITLE="❓ Claude 想问你"
    ICON="$ICON_QUESTION"
    SOUND="Glass"
    BARK_LEVEL="timeSensitive"
    BARK_SOUND="bell"
    BARK_CALL="0"
    BARK_VOLUME="5"
    ;;
  done)
    TITLE="✅ Claude 处理完了"
    ICON="$ICON_DONE"
    SOUND="Ping"
    BARK_LEVEL="timeSensitive"
    BARK_SOUND="birdsong"
    BARK_CALL="0"
    BARK_VOLUME="3"
    ;;
esac

# ── Background: poll focus for DELAY; cancel if terminal gets focus, else notify ──
(
  ELAPSED=0
  while [ "$ELAPSED" -lt "$DELAY" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    if [ "$(front_app)" = "$TARGET_APP" ]; then
      exit 0   # terminal regained focus → present → cancel
    fi
  done

  # Terminal never regained focus during DELAY — alert.
  if [ -x "$TN" ]; then
    "$TN" \
      -title "$TITLE" \
      -subtitle "$PROJECT" \
      -message "$MSG" \
      -sound "$SOUND" \
      -activate "$TARGET_APP" \
      -group "claude-code-notify" >/dev/null 2>&1 || true
  fi

  # Bark push (JSON). Rich params: level/sound/call/volume/group/badge/icon.
  if [ "$BARK_KEY" != "YOUR_BARK_KEY" ]; then
    PAYLOAD="$(jq -n \
      --arg t "$TITLE" --arg st "$PROJECT" --arg b "$MSG" \
      --arg lvl "$BARK_LEVEL" --arg snd "$BARK_SOUND" \
      --arg call "$BARK_CALL" --argjson vol "$BARK_VOLUME" \
      --arg icon "$ICON" \
      '{title:$t, subtitle:$st, body:$b, level:$lvl, sound:$snd,
        call:$call, volume:$vol, icon:$icon, group:"Claude Code", badge:1}' 2>/dev/null)"
    curl -s --max-time 6 -X POST "$BARK_SERVER/$BARK_KEY" \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d "$PAYLOAD" >/dev/null 2>&1 || true
  fi
) >/dev/null 2>&1 &

# Return immediately so Claude is never blocked.
exit 0
