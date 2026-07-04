# cowork-memory-sync — Windows layout check
#
# Verifies the filesystem paths the plugin assumes on Windows. Run in
# PowerShell on the Windows machine (or paste into a Windows Claude Code
# session and ask it to "run this as PowerShell"). Paste the output back
# to whoever is maintaining the plugin.
#
# This checks PATHS only. It does NOT test whether Cowork's Bash tool is a
# POSIX-style shell — for that, run tools/cowork-shell-check.sh INSIDE a
# Cowork session.

Write-Host "== SHELL / OS =="
Write-Host "PSVersion : $($PSVersionTable.PSVersion)"
Write-Host "OS        : $([Environment]::OSVersion.VersionString)"
Write-Host "Hostname  : $env:COMPUTERNAME"
Write-Host ""

Write-Host "== APP INSTALL =="
@("$env:LOCALAPPDATA\Programs\Claude", "$env:ProgramFiles\Claude", "${env:ProgramFiles(x86)}\Claude") |
  ForEach-Object { "{0,-6} {1}" -f (Test-Path $_), $_ }
Write-Host ""

Write-Host "== APP DATA / SESSIONS  (plugin MEMORY_ROOT) =="
$sessions = "$env:APPDATA\Claude\local-agent-mode-sessions"
"{0,-6} {1}" -f (Test-Path $sessions), $sessions
if (Test-Path $sessions) {
  $n = (Get-ChildItem $sessions -Recurse -Filter ".sync-link.json" -File -ErrorAction SilentlyContinue).Count
  Write-Host ".sync-link.json files found: $n"
}
Write-Host ""

Write-Host "== CLOUD MOUNTS  (plugin CLOUD_ROOTS) =="
Get-ChildItem $env:USERPROFILE -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "OneDrive|Dropbox|iCloud|Box" } |
  ForEach-Object { $_.FullName }
Write-Host ""

Write-Host "== CONFIG_HOME =="
$cfg = "$env:USERPROFILE\.config\cowork-memory-sync"
"{0,-6} {1}" -f (Test-Path $cfg), $cfg
