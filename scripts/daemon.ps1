# =============================================================================
# wechat-claude-code Windows service installer
# Provides: auto-start on boot + auto-restart on crash (5-min check interval)
# Usage: powershell -ExecutionPolicy Bypass -File scripts/daemon.ps1 {install|uninstall|status}
# =============================================================================

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("install", "uninstall", "status")]
  [string]$Action
)

$ErrorActionPreference = "Stop"

$TaskName = "WeChatClaudeCodeBridge"
$TaskNameKeepalive = "WeChatClaudeCodeBridge-Keepalive"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$DaemonScript = "$ProjectDir\scripts\daemon.sh"

# Locate bash.exe
$BashExe = $null
$candidates = @(
  (Get-Command bash.exe -ErrorAction SilentlyContinue).Source,
  "C:\Program Files\Git\bin\bash.exe",
  "C:\Program Files (x86)\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
  "C:\msys64\usr\bin\bash.exe",
  "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
)
foreach ($c in $candidates) {
  if ($c -and (Test-Path $c)) { $BashExe = $c; break }
}
if (-not $BashExe) {
  Write-Host "Cannot find bash.exe. Please install Git for Windows first." -ForegroundColor Red
  exit 1
}

function Test-Admin {
  $isAdmin = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "Please run PowerShell as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    exit 1
  }
}

function Run-SchTasks {
  $cmdArgs = $args -join ' '
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "schtasks.exe"
  $psi.Arguments = $cmdArgs
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  return @{ ExitCode = $proc.ExitCode; Output = $stdout; Error = $stderr }
}

function Install-Service {
  Test-Admin

  Write-Host "[1/2] Creating auto-start task..." -ForegroundColor Green
  $startupAction = "$BashExe -c `"cd '$ProjectDir'; bash '$DaemonScript' start`""
  $result = Run-SchTasks /create /tn $TaskName /sc ONLOGON /delay 0000:30 /tr $startupAction /f /rl HIGHEST
  if ($result.ExitCode -eq 0) {
    Write-Host "  OK: $TaskName" -ForegroundColor Gray
  } else {
    Write-Host "  FAILED: $($result.Error)" -ForegroundColor Red
    exit 1
  }

  Write-Host "[2/2] Creating keepalive task (every 5 min)..." -ForegroundColor Green
  $keepaliveCmd = (
    "$BashExe",
    "-c",
    "PID_FILE=`$HOME/.wechat-claude-code/wechat-claude-code.pid; PROJECT_DIR='$ProjectDir'; if [ -f `$PID_FILE ]; then PID=`$(cat `$PID_FILE); if [ -n `$PID ] && kill -0 `$PID 2>/dev/null; then exit 0; fi; fi; cd `$PROJECT_DIR; bash scripts/daemon.sh start >> `$HOME/.wechat-claude-code/logs/keepalive.log 2>&1"
  ) -join ' '
  $result = Run-SchTasks /create /tn $TaskNameKeepalive /sc MINUTE /mo 5 /delay 0001:00 /tr $keepaliveCmd /f /rl HIGHEST
  if ($result.ExitCode -eq 0) {
    Write-Host "  OK: $TaskNameKeepalive" -ForegroundColor Gray
  } else {
    Write-Host "  FAILED: $($result.Error)" -ForegroundColor Red
    exit 1
  }

  Write-Host ""
  Write-Host "Done. The WeChat bridge will now:" -ForegroundColor Cyan
  Write-Host "  1. Start automatically 30s after login" -ForegroundColor White
  Write-Host "  2. Auto-restart within 5min if it crashes" -ForegroundColor White
  Write-Host ""
  Write-Host "To uninstall:" -ForegroundColor Cyan
  Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\daemon.ps1 uninstall" -ForegroundColor Gray
}

function Uninstall-Service {
  Test-Admin

  Write-Host "Removing scheduled tasks..." -ForegroundColor Yellow
  Run-SchTasks /delete /tn $TaskName /f | Out-Null
  Run-SchTasks /delete /tn $TaskNameKeepalive /f | Out-Null
  Write-Host "Uninstalled." -ForegroundColor Green
}

function Show-Status {
  Write-Host "=== Scheduled Tasks ===" -ForegroundColor Cyan
  foreach ($tn in @($TaskName, $TaskNameKeepalive)) {
    $result = Run-SchTasks /query /tn $tn /fo LIST
    if ($result.ExitCode -eq 0) {
      $statusLine = ($result.Output -split "`n") | Select-String "Status:"
      $nextLine = ($result.Output -split "`n") | Select-String "Next Run Time:"
      Write-Host "[$tn]" -ForegroundColor White
      Write-Host "  $($statusLine -replace '\s+', ' ')" -ForegroundColor Gray
      Write-Host "  $($nextLine -replace '\s+', ' ')" -ForegroundColor Gray
    } else {
      Write-Host "[$tn] Not installed" -ForegroundColor Yellow
    }
  }
  Write-Host ""
  Write-Host "=== Process Status ===" -ForegroundColor Cyan
  $bashResult = & $BashExe -c "cd '$ProjectDir'; bash scripts/daemon.sh status" 2>&1
  Write-Host $bashResult
}

switch ($Action) {
  "install"   { Install-Service }
  "uninstall" { Uninstall-Service }
  "status"    { Show-Status }
}
