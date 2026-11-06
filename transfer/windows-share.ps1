<#
  Shared-folder bridge on Windows: create the folders, show exactly where they
  are, and keep both halves running in this one window.

    powershell -ExecutionPolicy Bypass -File .\windows-share.ps1
    ... -To 192.168.1.50      record the Mac's address (asked once)
    ... -Token <value>        record the shared token (asked once)

  Folders:
    Desktop\Shared\To Mac     drop files here, they go to the Mac
    Desktop\Shared\From Mac   files sent from the Mac land here

  Ctrl+C stops everything. Run as Administrator so the receiver can listen.
#>
param(
  [string]$To,
  [int]$Port = 8790,
  [string]$Token
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$share = Join-Path $env:USERPROFILE "Desktop\Shared"
$toMac = Join-Path $share "To Mac"
$fromMac = Join-Path $share "From Mac"
$tokenFile = Join-Path $env:APPDATA "mac-win-control\token"
$peerFile = Join-Path $env:APPDATA "mac-win-control\peer"

New-Item -ItemType Directory -Force -Path $toMac, $fromMac | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $tokenFile) | Out-Null

if ($Token) { Set-Content -Path $tokenFile -Value $Token -Encoding ASCII }
if ($To)    { Set-Content -Path $peerFile  -Value $To    -Encoding ASCII }
elseif ($env:MAC_WIN_PEER) { $To = $env:MAC_WIN_PEER }
elseif (Test-Path $peerFile) { $To = (Get-Content $peerFile -Raw).Trim() }

if (-not (Test-Path $tokenFile)) {
  Write-Host ""
  Write-Host "  One thing missing: the shared token." -ForegroundColor Yellow
  Write-Host "  On the Mac run:  transfer/mac-receive.py --print-token"
  Write-Host "  then run this again with:  -Token <that value>" -ForegroundColor Yellow
  Write-Host ""
  exit 1
}
if (-not $To) {
  Write-Host ""
  Write-Host "  One thing missing: the Mac's address." -ForegroundColor Yellow
  Write-Host "  share.sh on the Mac prints it. Then run this again with: -To <mac-ip>"
  Write-Host ""
  exit 1
}
$token = (Get-Content $tokenFile -Raw).Trim()

Write-Host ""
Write-Host "  Mac  <->  Windows file sharing" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Drop files here to send them to the Mac:"
Write-Host "      $toMac" -ForegroundColor White
Write-Host ""
Write-Host "  Files sent from the Mac appear here:"
Write-Host "      $fromMac" -ForegroundColor White
Write-Host ""
Write-Host "  Mac address: $To   port $Port" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Opening the folder so you can drag things into it..." -ForegroundColor DarkGray
Start-Process explorer.exe -ArgumentList "`"$share`"" | Out-Null

$recv = Join-Path $here "windows-receive.ps1"
$watch = Join-Path $here "watched-folder.ps1"
foreach ($f in @($recv, $watch)) {
  if (-not (Test-Path $f)) { throw "missing $f - keep the transfer folder together." }
}

$job = Start-Job -Name macWinReceive -ScriptBlock {
  param($script, $port, $dir, $token)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Port $port -Dir $dir -Token $token
} -ArgumentList $recv, $Port, $fromMac, $token

try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $watch -To $To -Port $Port -Dir $toMac -Token $token
}
finally {
  Write-Host "  stopping..." -ForegroundColor DarkGray
  Stop-Job $job -ErrorAction SilentlyContinue
  Remove-Job $job -Force -ErrorAction SilentlyContinue
}
