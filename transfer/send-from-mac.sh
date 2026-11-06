#!/bin/bash
# Send files or folders from this Mac to the Windows machine.
#
#   ./send-from-mac.sh ~/Downloads/report.pdf ~/Pictures/shot.png
#   ./send-from-mac.sh ~/Projects/somefolder     # folders are tar.gz'd automatically
#   ./send-from-mac.sh --to <windows-ip> file
#
# The Windows machine must be running transfer/windows-receive.ps1.
# The shared token is read from ~/.config/mac-win-control/token.
set -u

TOKEN_FILE="$HOME/.config/mac-win-control/token"
PEER="${MAC_SEND_TO:-}"
PEER_FILE="$HOME/.config/mac-win-control/peer"
PORT="${MAC_SEND_PORT:-8790}"

usage() { sed -n '2,11p' "$0"; exit 0; }

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --to) PEER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) args+=("$1"); shift ;;
  esac
done

[ ${#args[@]} -gt 0 ] || usage
if [ -z "$PEER" ] && [ -r "$PEER_FILE" ]; then PEER="$(cat "$PEER_FILE")"; fi
if [ -z "$PEER" ]; then
  echo "No laptop address. Run share.sh start --to <laptop-ip> once, or set MAC_SEND_TO."
  exit 1
fi
if [ ! -r "$TOKEN_FILE" ]; then
  echo "No token at $TOKEN_FILE."
  echo "Run transfer/mac-receive.py --print-token and save that value there."
  exit 1
fi
TOKEN="$(cat "$TOKEN_FILE")"

tmpfiles=()
cleanup() { for t in ${tmpfiles[@]+"${tmpfiles[@]}"}; do rm -f "$t"; done; }
trap cleanup EXIT

post() {
  local src="$1" label="$2" enc code out err
  enc="$(/usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$label")"
  out="$(mktemp)"; err="$(mktemp)"
  code=$(curl -sS --max-time 1800 \
    -H "X-Token: $TOKEN" \
    -H "X-Filename: $enc" \
    --data-binary @"$src" \
    -o "$out" -w '%{http_code}' \
    "http://$PEER:$PORT/upload" 2>"$err") || code="000"
  if [ "$code" = "200" ]; then
    printf 'sent   %-40s -> %s  %s\n' "$label" "$PEER" "$(tr -d '\n' < "$out")"
    rm -f "$out" "$err"
    return 0
  fi
  printf 'FAILED %-40s http=%s  %s\n' "$label" "$code" "$(tr -d '\n' < "$err")"
  rm -f "$out" "$err"
  return 1
}

rc=0
for f in "${args[@]}"; do
  if [ ! -e "$f" ]; then echo "not found: $f"; rc=1; continue; fi
  if [ -d "$f" ]; then
    base="$(basename "$f")"
    tar_path="/tmp/mwc-$$-$base.tar.gz"
    if tar -czf "$tar_path" -C "$(dirname "$f")" "$base"; then
      tmpfiles+=("$tar_path")
      post "$tar_path" "$base.tar.gz" || rc=1
    else
      echo "could not tar $f"; rc=1
    fi
  else
    post "$f" "$(basename "$f")" || rc=1
  fi
done
exit $rc
