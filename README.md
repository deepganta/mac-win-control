# Mac ↔ Windows: one mouse, one keyboard, files that move

Two machines on one desk with no KVM and no cable swapping.

- **Cursor and keyboard.** Move the pointer off the right edge of the Mac screen
  and it appears on the Windows screen. Type, and it goes to whichever machine
  the pointer is on. This is Apple's Universal Control, rebuilt for Mac + Windows
  with [Deskflow](https://github.com/deskflow/deskflow) (open source, GPL).
- **Clipboard.** Copy text or an image on one machine, paste on the other.
  Comes free with Deskflow, nothing to start.
- **Files.** Drop a file in a folder on your Desktop and it appears on the other
  machine a second later. No cables, no cloud, nothing to upload.

Bluetooth is never touched, so a multi-device mouse keeps its single pairing.

## Where the folders are

Both machines get one visible folder on the Desktop. Nothing is hidden in a home
directory.

| Machine | Drop files here to send | Files sent to you arrive here |
|---|---|---|
| Mac | `~/Desktop/Shared/To Windows` | `~/Desktop/Shared/From Windows` |
| Windows | `%USERPROFILE%\Desktop\Shared\To Mac` | `%USERPROFILE%\Desktop\Shared\From Mac` |

Each helper prints those two paths on startup, so you can always confirm the
location before dragging anything.

## Setup

Deskflow does the cursor and clipboard. The `transfer/` folder does files.

### Mac (server)

```
cd ~/Desktop/universal-control/transfer
./share.sh --to <windows-ip> start     # prints the folders, starts both helpers
```

Copy the token it prints (`./mac-receive.py --print-token`) to the Windows side
once, as `-Token`.

### Windows (client)

Install Deskflow, set the machine name, point it at the Mac:

```
powershell -ExecutionPolicy Bypass -File .\windows-setup.ps1 -Server <mac-ip>
```

First connection: both machines show a fingerprint. Accept on both.

Then, as Administrator, for file sharing:

```
powershell -ExecutionPolicy Bypass -File .\windows-share.ps1 -To <mac-ip> -Token <token>
```

That creates `Desktop\Shared`, opens it in Explorer, and runs both halves in one
window. `-To` and `-Token` only need passing the first time; afterwards plain
`.\windows-share.ps1` uses the saved values.

## Day to day

- Mac: `transfer/share.sh start` (once per boot), then just drag files into
  `Desktop/Shared/To Windows`.
- Windows: `windows-share.ps1` (once per boot), drag files into
  `Desktop\Shared\To Mac`.
- Cursor and clipboard need nothing running beyond Deskflow itself.

## Sending one file without the folder

```bash
# macOS
./send-from-mac.sh ~/Desktop/report.pdf
./send-from-mac.sh ~/Pictures/album            # folders are tarred automatically
```

```powershell
# Windows
.\send-from-windows.ps1 C:\Users\me\Desktop\report.pdf
```

## How it works

`share.ps1`/`share.sh` start two small pieces on each side:

1. a receiver, an HTTP listener on TCP **8790** that writes uploads into the
   "From …" folder, protected by a shared token
2. a watcher, which polls the "To …" folder once a second and uploads anything
   new, once its size has stopped changing

Requests without the right token get 403. Filenames are reduced to a basename,
so `../../etc/passwd` cannot escape the folder. Duplicate names get ` (1)`,
` (2)` suffixes rather than overwriting. Tokens live in
`~/.config/mac-win-control/token` and `%APPDATA%\mac-win-control\token`, never in
this repo.

## Limits worth knowing

- A true cross-screen drag - file leaves the Finder and lands on the Windows
  desktop - is not possible with injected input events; the file must be handed
  to the other machine by something on both sides. Synergy 3, Deskflow's
  commercial sibling, is the only mainstream tool that implements it.
- Clipboard carries text, HTML and images, not files.
- Wireless adds a few ms. If the first seconds after an idle period feel sticky,
  that is the Windows Wi-Fi adapter's power saving: turn off "allow the computer
  to turn off this device" in Device Manager, and set the power plan to High
  performance.
- Both machines must be awake and on the same network.

## Troubleshooting

- Cursor won't cross: `transfer/mac-status.sh` on the Mac. It reports whether the
  server is listening, who is connected, and the screen layout.
- Files don't arrive: check the receiver window is still open on the destination,
  and that `share.sh status` shows `receiver: listening on 8790`.
- Wrong address after the network changed: rerun `share.sh --to <new-ip> start`
  and `windows-share.ps1 -To <new-ip>`.
- Deskflow release 1.27.0 crashes on macOS once a second screen is named; the
  continuous build (1.27.0.24) is the pinned workaround, and that is what this
  setup installs.
