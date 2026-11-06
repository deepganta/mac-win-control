<#
  Watch a folder and push anything dropped in it to the Mac.

    powershell -ExecutionPolicy Bypass -File .\watched-folder.ps1
    powershell -ExecutionPolicy Bypass -File .\watched-folder.ps1 -To <mac-ip>

  Drop target:  %USERPROFILE%\Desktop\Shared\To Mac
  Arrives at:   ~/Desktop/Shared/From Windows on the Mac (printed at startup)

  A file is sent only once its size stops changing, so a half-copied file is
  not shipped. Re-saving re-sends. Token comes from %APPDATA%\mac-win-control\token.
#>
param(
  [string]$To,
  [int]$Port = 8790,
  [string]$Dir = "$env:USERPROFILE\Desktop\Shared\To Mac",
  [int]$Interval = 1,
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
  throw "No Mac address yet. Pass -To <mac-ip> once (share.sh on the Mac prints it)."
}

if (-not $Token) {
  if (-not (Test-Path $tokenFile)) { throw "No token. Pass -Token, or run windows-share.ps1 -Token <value> first." }
  $Token = (Get-Content $tokenFile -Raw).Trim()
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Write-Host ""
Write-Host "  Drop files here to send them to the Mac:" -ForegroundColor Cyan
Write-Host "    $Dir"
Write-Host "  Sending to ${To}:$Port. Leave this window open."
Write-Host ""

# WebClient rather than HttpClient: Windows PowerShell 5.1 does not load
# System.Net.Http by default, and this has to work on a plain Windows box.
$wc = New-Object System.Net.WebClient
$sent = @{}
$failedAt = @{}
$prev = @{}

while ($true) {
  Start-Sleep -Seconds $Interval
  $cur = @{}
  Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Name.StartsWith(".") } |
    ForEach-Object { $cur[$_.Name] = "$($_.Length):$($_.LastWriteTimeUtc.Ticks)" }

  foreach ($name in $cur.Keys) {
    if (-not $prev.ContainsKey($name) -or $prev[$name] -ne $cur[$name]) { continue }
    if ($sent.ContainsKey($name) -and $sent[$name] -eq $cur[$name]) { continue }
    if ($failedAt.ContainsKey($name) -and ((Get-Date) - $failedAt[$name]).TotalSeconds -lt 10) { continue }

    $file = Join-Path $Dir $name
    try {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $wc.Headers.Set("X-Token", $Token)
      $wc.Headers.Set("X-Filename", [System.Uri]::EscapeDataString($name))
      [void]$wc.UploadData("http://$To`:$Port/upload", "POST", $bytes)
      $sent[$name] = $cur[$name]
      Write-Host "sent $name ($($bytes.Length) bytes) -> ${To}" -ForegroundColor Green
    }
    catch {
      $failedAt[$name] = Get-Date
      Write-Host "FAILED $name : $($_.Exception.Message)" -ForegroundColor Red
    }
  }
  $prev = $cur
}
