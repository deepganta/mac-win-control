#!/usr/bin/env python3
"""Receive files from the Windows laptop.

Runs on the Mac, listens on TCP 8790, writes uploads into
~/Desktop/Shared/From Windows.
Requires a shared token so the port is not an open dropbox on the network.

  ./mac-receive.py            # serve
  ./mac-receive.py --print-token

The token lives in ~/.config/mac-win-control/token (created on first run).
Protocol: POST /upload, headers X-Token, X-Filename (URL-encoded), body = bytes.
"""
import argparse
import base64
import http.server
import os
import pathlib
import secrets
import socketserver
import sys
import urllib.parse

TOKEN_PATH = pathlib.Path.home() / ".config" / "mac-win-control" / "token"
INBOX = pathlib.Path.home() / "Desktop" / "Shared" / "From Windows"
PORT = 8790


def load_token(create: bool = True) -> str:
    if TOKEN_PATH.exists():
        return TOKEN_PATH.read_text().strip()
    if not create:
        return ""
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    token = secrets.token_hex(16)
    TOKEN_PATH.write_text(token + "\n")
    TOKEN_PATH.chmod(0o600)
    return token


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "mac-win-control/1.0"
    token = ""

    def _reply(self, code: int, body: bytes = b"", ctype: str = "text/plain") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self) -> None:
        self._reply(200, b"ready\n")

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/upload":
            return self._reply(404, b"unknown path\n")
        if self.headers.get("X-Token", "") != self.token:
            return self._reply(403, b"bad token\n")

        raw_name = urllib.parse.unquote(self.headers.get("X-Filename", ""))
        name = os.path.basename(raw_name)
        if not name or name in {".", ".."}:
            return self._reply(400, b"bad filename\n")

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._reply(400, b"bad length\n")
        if length <= 0:
            return self._reply(400, b"empty body\n")

        INBOX.mkdir(parents=True, exist_ok=True)
        dest = INBOX / name
        stem, suffix = dest.stem, dest.suffix
        n = 1
        while dest.exists():
            dest = INBOX / f"{stem} ({n}){suffix}"
            n += 1

        remaining = length
        with dest.open("wb") as fh:
            while remaining > 0:
                chunk = self.rfile.read(min(65536, remaining))
                if not chunk:
                    break
                fh.write(chunk)
                remaining -= len(chunk)

        self._reply(200, f"saved {dest}\n".encode())

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[receive] " + (fmt % args) + "\n")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--print-token", action="store_true")
    ap.add_argument("--token", default=None, help="token expected from the sender")
    args = ap.parse_args()

    token = args.token or load_token()
    if args.print_token:
        print(token)
        return 0

    Handler.token = token
    INBOX.mkdir(parents=True, exist_ok=True)
    with Server(("0.0.0.0", args.port), Handler) as httpd:
        print("")
        print("  Files from Windows arrive here:")
        print(f"    {INBOX}")
        print(f"  Listening on port {args.port}. Leave this window open.")
        print("")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
