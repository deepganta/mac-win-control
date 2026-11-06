#!/usr/bin/env python3
"""Watch a folder and push anything dropped in it to the other machine.

Drag a file into ~/Desktop/Shared/To Windows and it lands in the
Windows inbox. Runs on the Mac.

  ./watched-folder.py                       # uses the saved peer address
  ./watched-folder.py --to <windows-ip> --dir "~/Desktop/Shared/To Windows"

A file is only sent once its size has stopped changing, so dropping a large
file mid-copy is safe. Re-saving a file re-sends it. Token comes from
~/.config/mac-win-control/token.
"""
import argparse
import pathlib
import sys
import time
import urllib.parse
import urllib.request

TOKEN_PATH = pathlib.Path.home() / ".config" / "mac-win-control" / "token"
PEER_PATH = pathlib.Path.home() / ".config" / "mac-win-control" / "peer"


def token() -> str:
    if not TOKEN_PATH.exists():
        sys.exit(f"no token at {TOKEN_PATH}")
    return TOKEN_PATH.read_text().strip()


def peer() -> str:
    if PEER_PATH.exists():
        return PEER_PATH.read_text().strip()
    sys.exit(
        "no peer address yet. Run share.sh start --to <laptop-ip> once, "
        f"or write the address into {PEER_PATH}"
    )


def send(path: pathlib.Path, host: str, port: int, tok: str, timeout: int = 1800) -> str:
    data = path.read_bytes()
    req = urllib.request.Request(
        f"http://{host}:{port}/upload",
        data=data,
        method="POST",
        headers={
            "X-Token": tok,
            "X-Filename": urllib.parse.quote(path.name),
            "Content-Type": "application/octet-stream",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode(errors="replace").strip()


def scan(dirpath: pathlib.Path) -> dict:
    out = {}
    try:
        for entry in dirpath.iterdir():
            if entry.is_dir() or entry.name.startswith("."):
                continue
            try:
                st = entry.stat()
            except OSError:
                continue
            out[entry.name] = (st.st_size, int(st.st_mtime))
    except FileNotFoundError:
        dirpath.mkdir(parents=True, exist_ok=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--to", default=None)
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--dir", default=str(pathlib.Path.home() / "Desktop" / "Shared" / "To Windows"))
    ap.add_argument("--interval", type=float, default=1.0)
    args = ap.parse_args()

    tok = token()
    host = args.to or peer()
    args.to = host
    folder = pathlib.Path(args.dir).expanduser()
    folder.mkdir(parents=True, exist_ok=True)
    print("")
    print("  Drop files here to send them to Windows:")
    print(f"    {folder}")
    print(f"  Sending to {args.to}:{args.port}. Leave this window open.")
    print("", flush=True)

    sent: dict = {}
    failed_at: dict = {}
    prev = scan(folder)
    while True:
        time.sleep(args.interval)
        cur = scan(folder)
        for name, sig in cur.items():
            if prev.get(name) != sig:      # still changing, wait for it to settle
                continue
            if sent.get(name) == sig:      # already delivered this version
                continue
            if time.time() - failed_at.get(name, 0) < 10:   # back off after a failure
                continue
            try:
                msg = send(folder / name, args.to, args.port, tok)
                sent[name] = sig
                print(f"sent {name} ({sig[0]} bytes) {msg}", flush=True)
            except Exception as exc:       # noqa: BLE001 - keep the watcher alive
                failed_at[name] = time.time()
                print(f"FAILED {name}: {exc}", flush=True)
        prev = cur


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        pass
