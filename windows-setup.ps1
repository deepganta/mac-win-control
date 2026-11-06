#Requires -RunAsAdministrator
<#
  Deskflow client setup for the Windows laptop.
  Installs Deskflow, names this machine LAPTOP, points it at the Mac, starts it.

  Run in PowerShell as Administrator, from the folder this file is in:
    powershell -ExecutionPolicy Bypass -File .\windows-setup.ps1 -Server <mac-ip>

  Use -Server <tailscale-ip> instead if the two machines are ever
  on different networks.

  What it changes on this PC:
    - installs Deskflow (GPL, open source, signed MSI from GitHub)
    - writes %APPDATA%\Deskflow\Deskflow.conf (client mode, server IP, name LAPTOP)
    - adds an inbound firewall rule for TCP 24800
    - starts the app once
  Nothing is set to run at login. Ask if you want that.
#>
param(
  [string]$Server,
  [string]$ClientName = "LAPTOP",
  [string]$MsiUrl     = "https://github.com/deskflow/deskflow/releases/download/continuous/deskflow-continuous-win-x64.msi"
)

$ErrorActionPreference = "Stop"
$peerFile = Join-Path $env:APPDATA "mac-win-control\peer"
if ($Server) {
  New-Item -ItemType Directory -Force -Path (Split-Path $peerFile) | Out-Null
  Set-Content -Path $peerFile -Value $Server -Encoding ASCII
} elseif (Test-Path $peerFile) {
  $Server = (Get-Content $peerFile -Raw).Trim()
} else {
  throw "Pass -Server <mac-ip> once (share.sh on the Mac prints its address)."
}
Write-Host "=== Deskflow client setup ===" -ForegroundColor Cyan

$msi = Join-Path $env:TEMP "deskflow-win-x64.msi"
if (-not (Test-Path $msi)) {
  Write-Host "Downloading Deskflow..."
  Invoke-WebRequest -Uri $MsiUrl -OutFile $msi -UseBasicParsing
}

Write-Host "Installing..."
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
Write-Host "msiexec exit code: $($p.ExitCode)  (0 or 3010 means success)"

$exe = @(
  "$env:ProgramFiles\Deskflow\Deskflow.exe",
  "${env:ProgramFiles(x86)}\Deskflow\Deskflow.exe",
  "$env:LOCALAPPDATA\Programs\Deskflow\Deskflow.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) {
  throw "Deskflow.exe not found after install. Launch Deskflow once from the Start menu, then re-run this script."
}
Write-Host "Installed at: $exe"

$confDir = Join-Path $env:APPDATA "Deskflow"
New-Item -ItemType Directory -Force -Path $confDir | Out-Null
$conf = Join-Path $confDir "Deskflow.conf"

$ini = @"
[core]
computerName=$ClientName
coreMode=1
lastVersion=1.27.0.0

[client]
remoteHost=$Server

[gui]
startCoreWithGui=true
logExpanded=true

[log]
level=Info
"@
Set-Content -Path $conf -Value $ini -Encoding ASCII
Write-Host "Wrote $conf"

New-NetFirewallRule -DisplayName "Deskflow 24800" -Direction Inbound -Protocol TCP -LocalPort 24800 -Action Allow -ErrorAction SilentlyContinue | Out-Null

Write-Host "Starting Deskflow..."
Start-Process $exe

Write-Host ""
Write-Host "Done. Deskflow is in client mode, pointed at $Server." -ForegroundColor Green
Write-Host "First connection: both machines show a fingerprint. Accept on both."
Write-Host "If a security agent blocks the installer, that is the corporate EDR, not this script."
