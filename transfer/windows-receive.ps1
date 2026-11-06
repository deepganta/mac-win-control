#Requires -RunAsAdministrator
<#
  Receive files sent from the Mac. Writes them to Desktop\Shared\From Mac.

  First time only, on the Mac:
    ~/Desktop/universal-control/transfer/mac-receive.py --print-token
  copy that value, then on Windows:

    powershell -ExecutionPolicy Bypass -File .\windows-receive.ps1 -Token <token> -Install

  That saves the token and opens the firewall port. Afterwards just:
    powershell -ExecutionPolicy Bypass -File .\windows-receive.ps1

  Protocol: POST /upload, headers X-Token and X-Filename (URL-encoded), body = file bytes.
#>
param(
  [int]$Port = 8790,
  [string]$Token,
  [string]$Dir = "$env:USERPROFILE\Desktop\Shared\From Mac",
  [switch]$Install
)

$ErrorActionPreference = "Stop"
$tokenFile = Join-Path $env:APPDATA "mac-win-control\token"

if ($Install) {
  if (-not $Token) { throw "-Token is required with -Install (run mac-receive.py --print-token on the Mac)" }
  New-Item -ItemType Directory -Force -Path (Split-Path $tokenFile) | Out-Null
  Set-Content -Path $tokenFile -Value $Token -Encoding ASCII
  New-NetFirewallRule -DisplayName "mac-win-control transfer $Port" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -ErrorAction SilentlyContinue | Out-Null
  & netsh http add urlacl "url=http://+:$Port/" user="$env:USERDOMAIN\$env:USERNAME" | Out-Null
  Write-Host "Installed. Token saved to $tokenFile, port $Port allowed, urlacl set." -ForegroundColor Green
  exit 0
}

if (-not $Token) {
  if (-not (Test-Path $tokenFile)) { throw "No token. Run once with -Token <value> -Install." }
  $Token = (Get-Content $tokenFile -Raw).Trim()
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()
Write-Host ""
Write-Host "  Files from the Mac arrive here:" -ForegroundColor Cyan
Write-Host "    $Dir"
Write-Host "  Listening on port $Port. Leave this window open."
Write-Host ""
Write-Host "Ctrl+C to stop."

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    if ($req.HttpMethod -ne "POST" -or $req.Url.AbsolutePath.TrimEnd("/") -ne "/upload") {
      $res.StatusCode = 404; $msg = "unknown path"
    }
    elseif ($req.Headers["X-Token"] -ne $Token) {
      $res.StatusCode = 403; $msg = "bad token"
    }
    else {
      $name = [System.Uri]::UnescapeDataString($req.Headers["X-Filename"])
      $name = [System.IO.Path]::GetFileName($name)
      if ([string]::IsNullOrWhiteSpace($name)) {
        $res.StatusCode = 400; $msg = "bad filename"
      }
      else {
        $dest = Join-Path $Dir $name
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext  = [System.IO.Path]::GetExtension($name)
        $n = 1
        while (Test-Path $dest) { $dest = Join-Path $Dir "$base ($n)$ext"; $n++ }
        $fs = [System.IO.File]::Create($dest)
        $req.InputStream.CopyTo($fs)
        $fs.Close()
        $res.StatusCode = 200; $msg = "saved $dest"
        Write-Host "received $name -> $dest" -ForegroundColor Green
      }
    }
  }
  catch {
    $res.StatusCode = 500; $msg = $_.Exception.Message
    Write-Host "error: $msg" -ForegroundColor Red
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes("$msg`n")
  $res.ContentLength64 = $bytes.Length
  try { $res.OutputStream.Write($bytes, 0, $bytes.Length) } catch { }
  $res.Close()
}
