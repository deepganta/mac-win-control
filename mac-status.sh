#!/bin/zsh
# Mac side of the Mac -> Windows control bridge.
# Usage: ./mac-status.sh [start|stop|status|watch]
set -u

APP="/Applications/Deskflow.app"
CORE="$APP/Contents/MacOS/deskflow-core"
CONF="$HOME/Library/Deskflow/Deskflow.conf"
SERVER_CONF="$HOME/Library/Deskflow/deskflow-server.conf"
GUI="$APP/Contents/MacOS/Deskflow"

status() {
  if [ -d "$APP" ]; then
    echo "app:      $("$GUI" --version 2>/dev/null | grep -m1 'Deskflow:')"
  else
    echo "app:      not installed"
  fi
  echo "server:   $(lsof -nP -iTCP:24800 -sTCP:LISTEN >/dev/null 2>&1 && echo 'listening on 24800' || echo 'not running')"
  echo "lan ip:   $(ipconfig getifaddr en0 2>/dev/null || echo none)   tailscale: $(tailscale ip -4 2>/dev/null | head -1)"
  echo "screens:  $(grep -E '^screens\\[0-9]+\\name=.' "$CONF" 2>/dev/null | sed 's/screens\\//;s/\\name=/: /' | tr '\n' ' ')"
  echo "links:    $(grep -A2 'section: links' "$SERVER_CONF" 2>/dev/null | tail -n +2 | tr -s ' \t' ' ' | tr '\n' ' ')"
}

case "${1:-status}" in
  start)
    pgrep -f "$GUI" >/dev/null || (nohup "$GUI" > /tmp/deskflow.log 2>&1 &)
    sleep 3; status ;;
  stop)
    osascript -e 'quit app "Deskflow"' 2>/dev/null; sleep 1; status ;;
  watch)
    tail -f /tmp/deskflow.log ;;
  *)
    status ;;
esac
