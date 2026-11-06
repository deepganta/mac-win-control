#!/bin/bash
# Shared-folder bridge: show the folders, start the two background helpers.
#
#   ./share.sh start     create the folders, start receiving + watching
#   ./share.sh stop
#   ./share.sh status
#   ./share.sh open      show the folder in Finder
#
# Folders (both live in one place you can see):
#   ~/Desktop/Shared/To Windows    drop files here, they go to the laptop
#   ~/Desktop/Shared/From Windows  files sent from the laptop land here
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SHARE="$HOME/Desktop/Shared"
TO_WIN="$SHARE/To Windows"
FROM_WIN="$SHARE/From Windows"
PEER="${MAC_SEND_TO:-}"
PEER_FILE="$HOME/.config/mac-win-control/peer"
PORT="${MAC_SEND_PORT:-8790}"
TOKEN_FILE="$HOME/.config/mac-win-control/token"
LOG=/tmp/mac-win-control.log

banner() {
  cat <<EOF

  Mac  <->  Windows file sharing

  Drop files here to send them to the laptop:
      $TO_WIN

  Files sent from the laptop appear here:
      $FROM_WIN

  Laptop address: $PEER   port $PORT
EOF
  if [ ! -r "$TOKEN_FILE" ]; then
    echo
    echo "  No token yet. Run this once and copy the value into the Windows setup:"
    echo "      $HERE/mac-receive.py --print-token"
  fi
  echo
}

ensure() {
  mkdir -p "$TO_WIN" "$FROM_WIN"
  if [ ! -r "$TOKEN_FILE" ]; then
    "$HERE/mac-receive.py" --print-token >/dev/null
  fi
}

running() { pgrep -f "mac-receive.py" >/dev/null || pgrep -f "watched-folder.py" >/dev/null; }

ACTION="start"
while [ $# -gt 0 ]; do
  case "$1" in
    --to) PEER="$2"; shift 2 ;;
    --to=*) PEER="${1#--to=}"; shift ;;
    --port) PORT="$2"; shift 2 ;;
    start|stop|status|open) ACTION="$1"; shift ;;
    -h|--help) ACTION=help; shift ;;
    *) shift ;;
  esac
done

if [ -z "$PEER" ] && [ -r "$PEER_FILE" ]; then PEER=$(cat "$PEER_FILE"); fi

case "$ACTION" in
  start)
    ensure
    if [ -n "$PEER" ]; then
      mkdir -p "$(dirname "$PEER_FILE")"
      printf '%s\n' "$PEER" > "$PEER_FILE"
    elif [ -r "$PEER_FILE" ]; then
      PEER="$(cat "$PEER_FILE")"
    else
      echo "No laptop address. Run:  ./share.sh --to <laptop-ip> start"
      exit 1
    fi
    pkill -f "mac-receive.py" 2>/dev/null; pkill -f "watched-folder.py" 2>/dev/null
    sleep 1
    ( cd "$HERE" && nohup ./mac-receive.py --port "$PORT" >> "$LOG" 2>&1 & )
    ( cd "$HERE" && MAC_SEND_TO="$PEER" MAC_SEND_PORT="$PORT" nohup ./watched-folder.py \
        --to "$PEER" --port "$PORT" --dir "$TO_WIN" >> "$LOG" 2>&1 & )
    sleep 2
    banner
    echo "  Started. Log: $LOG"
    echo
    open "$SHARE"
    ;;
  stop)
    pkill -f "mac-receive.py" 2>/dev/null; pkill -f "watched-folder.py" 2>/dev/null
    echo "stopped";;
  status)
    banner
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && echo "  receiver: listening on $PORT" || echo "  receiver: not running"
    pgrep -f "watched-folder.py" >/dev/null && echo "  watcher:  running" || echo "  watcher:  not running"
    echo;;
  open)
    ensure; open "$SHARE";;
  help)
    sed -n '2,12p' "$0"; exit 0;;
esac
