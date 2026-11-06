<#
  Send files from this Windows laptop to the Mac.

  The Mac must be running:  transfer/share.sh start

    powershell -ExecutionPolicy Bypass -File .\send-from-windows.ps1 C:\Users\me\Desktop\a.pdf

  Optional:
    -To <mac-ip>     remembered after the first time (stored in
                     %APPDATA%\mac-win-control\peer)
    -Port 8790
    -Token <value>   otherwise read from %APPDATA%\mac-win-control\token
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Files,
  [string]$To,
  [int]$Port = 8790,
  [string]$Token
)

$ErrorActionPreference = "Stop"
$peerFile = Join-Path $env:APPDATA "mac-win-control\peer"
$tokenFile = Join-Path $env:APPDATA "mac-win-control\token"
New-Item -ItemType Directory -Force -Path (Split-Path $peerFile) | Out-Null

if ($To) {
  Set-Content -Path $peerFile -Value $To -Encoding ASCII
} elseif ($env:MAC_WIN_PEER) {
  $To = $env:MAC_WIN_PEER
} elseif (Test-Path $peerFile) {
  $To = (Get-Content $peerFile -Raw).Trim()
} else {
  throw "No Mac address yet. Run transfer/share.sh on the Mac (it prints its address), then pass -To <mac-ip> once."
}

if (-not $Token) {
  if (-not (Test-Path $tokenFile)) { throw "No token. Pass -Token <value> (see mac-receive.py --print-token on the Mac)." }
  $Token = (Get-Content $tokenFile -Raw).Trim()
}

# WebClient rather than HttpClient: Windows PowerShell 5.1 does not load
# System.Net.Http by default.
$wc = New-Object System.Net.WebClient
$fail = 0

foreach ($f in $Files) {
  if (-not (Test-Path $f)) { Write-Host "not found: $f" -ForegroundColor Red; $fail++; continue }
  $item = Get-Item $f
  if ($item.PSIsContainer) { Write-Host "skipping folder: $f (zip it first)" -ForegroundColor Yellow; $fail++; continue }

  try {
    $wc.Headers.Set("X-Token", $Token)
    $wc.Headers.Set("X-Filename", [System.Uri]::EscapeDataString($item.Name))
    [void]$wc.UploadData("http://$To`:$Port/upload", "POST", [System.IO.File]::ReadAllBytes($item.FullName))
    Write-Host "sent $($item.Name) -> $To" -ForegroundColor Green
  }
  catch {
    Write-Host "FAILED $($item.Name): $($_.Exception.Message)" -ForegroundColor Red
    $fail++
  }
}

exit $fail
