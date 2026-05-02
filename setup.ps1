# Setup - Registers AutoUpdate to start at user logon
# No admin required (uses HKCU Run key as fallback)

param(
    [int]$IdleMinutes = 10,
    [int]$CooldownHours = 6,
    [switch]$Remove
)

$scriptPath = Join-Path $PSScriptRoot "auto-update.ps1"
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -IdleMinutes $IdleMinutes -CooldownHours $CooldownHours"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$valueName = "AutoUpdate"

if ($Remove) {
    Write-Host "Removing auto-start entry..."

    # Try scheduled task first
    schtasks /Delete /TN $valueName /F 2>$null

    # Remove from registry
    Remove-ItemProperty -Path $runKey -Name $valueName -ErrorAction SilentlyContinue

    Write-Host "Done. AutoUpdate will no longer start at login."
    exit 0
}

Write-Host "Setting up auto-start for AutoUpdate..."

# Try scheduled task first (may need admin)
try {
    schtasks /Create /TN $valueName /TR "powershell.exe $arg" /SC ONLOGON /RL LIMITED /F 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [ok] Registered as scheduled task"
        exit 0
    }
} catch {}

# Fallback: registry Run key (no admin needed)
Write-Host "  [info] Scheduled task requires admin. Using registry Run key instead..."
Set-ItemProperty -Path $runKey -Name $valueName -Value "powershell.exe $arg" -Force
Write-Host "  [ok] Registered in HKCU\...\Run"

Write-Host ""
Write-Host "AutoUpdate will start silently at next login."
Write-Host "  Idle threshold : $IdleMinutes min"
Write-Host "  Cooldown       : $CooldownHours h"
Write-Host "  Logs           : $PSScriptRoot\logs\"
Write-Host ""
Write-Host "Run with -Remove to uninstall."
