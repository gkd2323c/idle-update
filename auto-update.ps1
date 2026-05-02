#Requires -Version 5.1
# AutoUpdate - Idle-triggered package manager auto-updater
# Detects system idle time, then runs winget / choco / scoop upgrades

param(
    [int]$IdleMinutes = 10,             # Minutes of idle before triggering
    [int]$CheckInterval = 30,           # Seconds between idle checks
    [int]$CooldownHours = 6,            # Min hours between full update cycles
    [switch]$RunOnce,                   # Run one cycle and exit
    [switch]$DryRun,                    # List upgrades without installing
    [string]$LogDir = "$PSScriptRoot\logs"
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "AutoUpdate"

# --- Ensure log directory ---
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$logFile = Join-Path $LogDir "autoupdate-$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# --- Idle detection via Win32 API ---
Add-Type @'
using System;
using System.Runtime.InteropServices;
public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
public class IdleDetector {
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")] static extern uint GetTickCount();
    public static uint GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO)) };
        if (!GetLastInputInfo(ref lii)) return 0;
        return (GetTickCount() - lii.dwTime) / 1000;
    }
}
'@

# --- State file for cooldown tracking ---
$stateFile = Join-Path $LogDir ".autoupdate-state.json"
function Get-State { if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json } else { @{} } }
function Set-State($state) { $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8 }

# --- Package manager detection ---
function Test-Command($cmd) { return (Get-Command $cmd -ErrorAction SilentlyContinue) -ne $null }

$managers = [ordered]@{}
if (Test-Command "winget")   { $managers["winget"] = $true }
if (Test-Command "choco")    { $managers["choco"]  = $true }
if (Test-Command "scoop")    { $managers["scoop"]  = $true }

if ($managers.Count -eq 0) {
    Write-Log "No supported package manager found (winget, choco, scoop). Exiting." "ERROR"
    exit 1
}

$managerNames = ($managers.Keys -join ", ")
Write-Log "Detected package managers: $managerNames"

# --- Update functions ---

function Invoke-WingetUpgrade {
    Write-Log "--- winget upgrade starting ---"
    try {
        if ($DryRun) {
            winget upgrade --include-unknown | Out-String | ForEach-Object { Write-Log $_ }
        } else {
            $proc = Start-Process -FilePath "winget" -ArgumentList "upgrade --all --silent --accept-package-agreements --accept-source-agreements" -Wait -NoNewWindow -PassThru
            Write-Log "winget exited with code $($proc.ExitCode)" ("INFO", "WARN")[$proc.ExitCode -ne 0]
        }
    } catch {
        Write-Log "winget error: $_" "ERROR"
    }
}

function Invoke-ChocoUpgrade {
    Write-Log "--- choco upgrade starting ---"
    try {
        $args = if ($DryRun) { "outdated" } else { "upgrade all -y --limit-output" }
        $proc = Start-Process -FilePath "choco" -ArgumentList $args -Wait -NoNewWindow -PassThru
        Write-Log "choco exited with code $($proc.ExitCode)" ("INFO", "WARN")[$proc.ExitCode -ne 0]
    } catch {
        Write-Log "choco error: $_" "ERROR"
    }
}

function Invoke-ScoopUpdate {
    Write-Log "--- scoop update starting ---"
    try {
        if ($DryRun) {
            scoop status 2>&1 | ForEach-Object { Write-Log $_ }
        } else {
            $proc = Start-Process -FilePath "scoop" -ArgumentList "update" -Wait -NoNewWindow -PassThru
            Write-Log "scoop update exited with code $($proc.ExitCode)"
            $proc2 = Start-Process -FilePath "scoop" -ArgumentList "update *" -Wait -NoNewWindow -PassThru
            Write-Log "scoop update * exited with code $($proc2.ExitCode)"
        }
    } catch {
        Write-Log "scoop error: $_" "ERROR"
    }
}

function Run-Updates {
    Write-Log "========== Starting update cycle =========="
    $start = Get-Date

    if ($managers.ContainsKey("winget")) { Invoke-WingetUpgrade }
    if ($managers.ContainsKey("choco"))  { Invoke-ChocoUpgrade }
    if ($managers.ContainsKey("scoop"))  { Invoke-ScoopUpdate }

    $elapsed = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
    Write-Log "========== Update cycle complete ($elapsed min) =========="
}

# --- Main loop ---
Write-Log "AutoUpdate started (idle=${IdleMinutes}min, interval=${CheckInterval}s, cooldown=${CooldownHours}h)"
Write-Log "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'LIVE' })"

while ($true) {
    $idleSec = [IdleDetector]::GetIdleSeconds()
    $state = Get-State

    if ($idleSec -ge ($IdleMinutes * 60)) {
        # Check cooldown
        $lastRun = if ($state.lastRun) { [datetime]$state.lastRun } else { [datetime]::MinValue }
        $hoursSince = [math]::Round(((Get-Date) - $lastRun).TotalHours, 1)

        if ($hoursSince -ge $CooldownHours) {
            Write-Log "System idle for $([math]::Round($idleSec / 60, 0)) min. Cooldown passed ($hoursSince h since last run). Running updates..."

            # Mark state immediately to prevent parallel runs
            $state.lastRun = (Get-Date).ToString("o")
            Set-State $state

            Run-Updates

            if ($RunOnce) {
                Write-Log "RunOnce mode: exiting."
                exit 0
            }
        } else {
            $idle = [math]::Round($idleSec / 60, 0)
            Write-Log "Idle ($idle min) but cooldown not met ($hoursSince / $CooldownHours h). Waiting..."
        }
    }

    Start-Sleep -Seconds $CheckInterval
}
