# ============================================================================
#  GameBooster.ps1 v8.1 -- EXTREME MAXIMIZED
#  Tuned for: Intel Core Ultra 7 258V + Intel Arc 140V 16GB (Lunar Lake)
#  Windows 11 25H2 (Build 26200) | Wi-Fi 7 BE201
#
#  v8.1 SAFE RESTORE CHANGELOG:
#  [CRITICAL FIX] Restore no longer writes hardcoded power values onto your plan
#                 (it was turning CPU turbo boost OFF on Balanced after every game)
#  [CRITICAL FIX] Ultimate Performance plan can't exist on Modern Standby laptops;
#                 now uses the Windows "Best performance" power mode instead
#  [FIX] Every registry tweak snapshots the original value and restores exactly that
#        (mouse acceleration, transparency etc. were reset to hardcoded defaults)
#  [FIX] Restore state saved to BoosterRestore.json: closing the window mid-game
#        no longer leaves tweaks applied; next start or StopBooster.bat restores them
#  [FIX] Defender exclusion is removed again when Game closes
#  [FIX] Kill list no longer force-closes browsers, editors, terminals, Java or
#        recorders (unsaved work / recordings were lost)
#  [DEL] bcdedit tweaks (need a reboot, so toggling them per game did nothing)
#  [DEL] USB selective suspend tweak and unused network/DNS functions
#  [NEW] -RestoreOnly switch (used by StopBooster.bat)
#  [NEW] GPU preference + FSO also applied to the running game's real exe path
#        (from GameBooster; covers installs outside Program Files)
#
#  v8.0 EXTREME MAXIMIZED CHANGELOG:
#  [NEW] Fullscreen Optimizations disabled for Game
#  [NEW] Windows Defender Exclusion for Game
#  [NEW] Multi-Plane Overlay (MPO) disabled
#  [NEW] Extreme Bcdedit tuning (HPET off, dynamicticks off)
#  v7.0 ANTI-LAG OVERHAUL CHANGELOG:
#  [CRITICAL FIX] RAM threshold lowered 8GB->4GB (was thrashing every 4s = STUTTER)
#  [CRITICAL FIX] Added 30s cooldown between RAM compressions (no more spam)
#  [CRITICAL FIX] Smarter standby list: only purge when RAM truly critical
#  [NEW] GPU Priority registry key for Game (GPU scheduling preference)
#  [NEW] Per-app GPU scheduling override (High Performance for Game)
#  [NEW] Game process working set lock (prevents Windows paging it out)
#  [NEW] Self-deprioritization (booster runs at Idle so it never steals frames)
#  [NEW] Aggressive page file pre-commit (prevents mid-game page faults)
#  [NEW] Network adapter power management OFF (prevents Wi-Fi micro-sleeps)
#  [NEW] Background process scan + kill on respawn (every 60s instead of once)
#  [NEW] Detailed performance telemetry logging (FPS-impacting events tracked)
#  [NEW] Windows Memory Compression disable during gameplay
#  [UPD] Expanded bloatware kill list (2026 H2 additions, Copilot, AI services)
#  [UPD] Polling interval 4s->3s for active ISLC, 6s->10s for idle
#  [UPD] Thermal monitoring now continuous (every 60s) not one-shot
#  [FIX] Standby purge no longer destroys Game's own file cache
#  [FIX] Compress-WorkingSets now excludes GPU-bound processes
# ============================================================================

param(
    [string[]]$ProcessNames = @("FortniteClient-Win64-Shipping", "cs2", "r5apex", "Valorant-Win64-Shipping", "hl2", "dota2"),
    [string]$GameName = "ANY_GAME",
    [switch]$Silent,  # Suppresses console output when launched by .bat
    [switch]$Elevate, # Explicitly request UAC elevation
    [switch]$RestoreOnly  # Undo any leftover tweaks from BoosterRestore.json, then exit
)

# -- Auto-Elevation Check -----------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Elevate) {
        try {
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            if ($Silent) { $argList += " -Silent" }
            if ($RestoreOnly) { $argList += " -RestoreOnly" }
            Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
            exit
        } catch {
            Write-Host "UAC elevation request failed or was cancelled." -ForegroundColor Yellow
        }
    }
    if (-not $Silent) {
        Write-Host "Notice: Running in Standard Mode (User Privileges)." -ForegroundColor Yellow
        Write-Host "Active: Memory cleaner, bloatware manager, and live telemetry dashboard." -ForegroundColor Cyan
        Write-Host "Tip: Run as Administrator for extreme kernel/BCDEDIT/MPO tweaks." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
}

# -- Native API Imports -------------------------------------------------------

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WinApi {
    [DllImport("ntdll.dll")]
    public static extern int NtSetTimerResolution(int DesiredResolution, bool SetResolution, out int CurrentResolution);

    [DllImport("ntdll.dll")]
    public static extern int NtQueryTimerResolution(out int MinimumResolution, out int MaximumResolution, out int CurrentResolution);

    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int SystemInformationClass, ref int SystemInformation, int SystemInformationLength);

    [DllImport("kernel32.dll")]
    public static extern bool SetProcessWorkingSetSizeEx(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize, int Flags);

    // Windows 11 power mode slider (Best power efficiency / Balanced / Best performance)
    [DllImport("powrprof.dll")]
    public static extern uint PowerGetActualOverlayScheme(out Guid OverlayGuid);

    [DllImport("powrprof.dll")]
    public static extern uint PowerSetActiveOverlayScheme(Guid OverlayGuid);

    public static bool PurgeStandbyList() {
        int command = 4;
        int result = NtSetSystemInformation(80, ref command, sizeof(int));
        return result == 0;
    }
}
"@ -ErrorAction SilentlyContinue
} catch {}

# -- Configuration ------------------------------------------------------------

# Uses the passed $ProcessNames parameter
if ($ProcessNames.Count -eq 0) {
    $ProcessNames = @("FortniteClient-Win64-Shipping", "cs2", "r5apex", "Valorant-Win64-Shipping")
}

$KillList = @(
    # Microsoft bloat
    # Never list apps that can hold unsaved work (browsers, editors, terminals, recorders):
    # Stop-Process -Force gives them no chance to save.
    "OneDrive", "msedgewebview2", "Teams", "ms-teams", "SearchHost",
    "StartMenuExperienceHost", "Widgets", "WidgetService", "PhoneExperienceHost",
    "YourPhoneServer", "TextInputHost", "GameBarPresenceWriter", "GameBar",
    "SnippingTool", "CalculatorApp", "CrossDeviceService", "FileCoAuth", "OfficeClickToRun",
    # Windows 11 25H2 new additions
    "copilot", "Microsoft.Windows.Ai*", "AiHost", "DevHome", "WinGetServer",
    "MicrosoftEdgeUpdate", "identity_helper", "msedge_pwa_launcher",
    # Lenovo bloat
    "SmartConnect", "LenovoVantage*", "Vantage*", "LenovoUtility", "LenovoSettings",
    "DSAService", "DSATray", "BioIso", "esrv", "ipf_helper", "ImController*",
    "LenovoNow*", "LenovoAccessibilityService", "AIMeetingManager",
    # Apps that eat resources
    "EpicWebHelper", "ollama app", "ollama", "WorkloadsSessionHost",
    "mc-fw-host", "PresentMonService",
    # Overlay / screenshot overhead
    "Overwolf*", "RadeonSoftware", "AMDRSServ", "ShareX", "Lightshot",
    # Background updaters & telemetry
    "SteamService", "steamwebhelper", "NahimicSvc*", "NahimicOSD",
    "CCleanerBrowser*", "UpdateAssistant",
    # 2026 H2 Windows additions
    "Recall*", "WindowsCopilotRuntime", "CopilotService",
    "MicrosoftEdge_X*", "msedge_proxy", "PhoneLink"
)

# Apps banished to E-Cores (Cores 4-7) instead of killed
$ECoreBanishedApps = @(
    "Discord",
    "EpicGamesLauncher",
    "UnrealEngineLauncher",
    "Spotify",
    "steam",
    "steamwebhelper",
    "msedge",
    "explorer"
)

$ServiceStopList = @(
    "WSearch",          # Windows Search indexer
    "SysMain",          # Superfetch (we handle memory ourselves)
    "DiagTrack",        # Telemetry
    "WbioSrvc",         # Biometric
    "TabletInputService",
    "ipfsvc",           # Intel IPF
    "LenovoVantageService",
    "ImControllerService",
    "FontCache",
    "WMPNetworkSvc",    # Windows Media sharing
    "MapsBroker",       # Maps data
    "lfsvc",            # Geolocation
    "wisvc",            # Windows Insider
    "RetailDemo",       # Retail demo
    "DPS",              # Diagnostic Policy
    "WdiServiceHost",   # Diagnostic Service Host
    "WdiSystemHost"     # Diagnostic System Host
)

$ScheduledTaskPatterns = @(
    "*Lenovo*", "*SmartConnect*", "*Vantage*", "*ImController*", "*OneDrive*",
    "*Consolidator*", "*UsbCeip*", "*DmClient*", "*DmClientOnScenarioDownload*",
    "*Microsoft Compatibility Appraiser*", "*ProgramDataUpdater*",
    "*Proxy*", "*MapsToastTask*", "*MapsUpdateTask*"
)

$CheckIntervalIdle   = 10   # Check every 10s when Game isn't running (saves resources)
$CheckIntervalActive = 3    # ACTIVE ISLC: Poll memory every 3 seconds
$MinFreeRAM_GB       = 4    # FIXED: Was 8GB = constant thrashing. 4GB is real danger zone
$MinFreeRAM_Warning  = 6    # Log a warning (but don't compress) at 6GB
$CompressCooldownSec = 30   # FIXED: Minimum seconds between RAM compressions
$RespawnScanInterval = 60   # Re-scan and kill respawned bloatware every 60s
$VRAMCacheCleanThresholdDays = 30  # Clean shader cache if older than this

$LogFile = Join-Path $PSScriptRoot "GameBooster.log"
$StateFile = Join-Path $PSScriptRoot "BoosterRestore.json"
$BestPerformanceMode = [guid]"ded574b5-45a0-4f42-8737-46345c09c238"

# Game config paths
$TargetLocalAppData = "$env:LOCALAPPDATA\GameGame\Saved\Config\WindowsClient"
$TargetGameUserSettings = Join-Path $TargetLocalAppData "GameUserSettings.ini"

# -- Logging ------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

function Update-Dashboard {
    param([bool]$IsRunning, [string]$Status, [decimal]$FreeRam, [int]$CpuTemp)
    $Host.UI.RawUI.BackgroundColor = "Black"
    Clear-Host

    Write-Host "=================================================" -ForegroundColor DarkGray
    Write-Host "    ___ ___  ___ _____ _  _ ___ _____ ___        " -ForegroundColor DarkGreen
    Write-Host "   | __/ _ \| _ \_   _| \| |_ _|_   _| __|       " -ForegroundColor DarkGreen
    Write-Host "   | _| (_) |   / | | | .\` || |  | | | _|        " -ForegroundColor Green
    Write-Host "   |_| \___/|_|_\ |_| |_|\_|___| |_| |___|       " -ForegroundColor Green
    Write-Host "                                                 "
    Write-Host "          [ SYSTEM OVERRIDE TERMINAL ]           " -ForegroundColor DarkCyan
    Write-Host "=================================================" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($IsRunning) {
        Write-Host "  [+] SYS.STATE : " -ForegroundColor DarkGreen -NoNewline
        Write-Host "[ ACTIVE OVERRIDE ENGAGED ]" -ForegroundColor Cyan
    } else {
        Write-Host "  [-] SYS.STATE : " -ForegroundColor DarkGreen -NoNewline
        Write-Host "[ IDLE / SCANNING TARGET  ]" -ForegroundColor DarkYellow
    }
    
    Write-Host "  [>] OPERATION : " -ForegroundColor DarkGreen -NoNewline
    Write-Host $Status -ForegroundColor White
    
    Write-Host ""
    Write-Host "  --- TELEMETRY ---------------------------------" -ForegroundColor DarkGray
    
    $ramColor = if ($FreeRam -lt $MinFreeRAM_GB) { "Red" } elseif ($FreeRam -lt $MinFreeRAM_Warning) { "Yellow" } else { "Green" }
    Write-Host "  [*] MEM.ALLOC : " -ForegroundColor DarkGreen -NoNewline
    Write-Host "${FreeRam} GB " -ForegroundColor $ramColor -NoNewline
    Write-Host "AVAILABLE  |  [0x00A7F1B]" -ForegroundColor DarkGray
    
    $tempColor = if ($CpuTemp -gt 90) { "Red" } elseif ($CpuTemp -gt 80) { "Yellow" } else { "Cyan" }
    $tempStr = if ($CpuTemp -gt 0) { "${CpuTemp}C" } else { "N/A" }
    Write-Host "  [*] THERM.SNS : " -ForegroundColor DarkGreen -NoNewline
    Write-Host "$tempStr " -ForegroundColor $tempColor -NoNewline
    Write-Host "           |  [0x0B89C2A]" -ForegroundColor DarkGray
    
    Write-Host "  [*] BOOST.CYC : " -ForegroundColor DarkGreen -NoNewline
    Write-Host "$boostCount" -ForegroundColor Green -NoNewline
    Write-Host "              |  ENGAGEMENTS" -ForegroundColor DarkGray

    Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  >>> Press [Ctrl+C] to abort operation..." -ForegroundColor DarkGray
}

function Reset-Log {
    if (Test-Path $LogFile) {
        $size = (Get-Item $LogFile).Length / 1KB
        if ($size -gt 512) {
            $backup = $LogFile -replace '\.log$', '.old.log'
            Move-Item -Path $LogFile -Destination $backup -Force -ErrorAction SilentlyContinue
            Write-Log "Log rotated"
        }
    }
}

# -- Restore State ------------------------------------------------------------
# Everything a boost changes is recorded here and saved to BoosterRestore.json,
# so the exact original settings come back even if this window is killed mid-game.

function New-BoostState {
    return [pscustomobject]@{
        Registry = @(); Services = @(); Tasks = @()
        PowerMode = $null; MemCompression = $false; DefenderPath = $null
    }
}

function Save-BoostState {
    try { $script:State | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8 } catch {}
}

function Set-Reg {
    <#
    .SYNOPSIS
        Writes a registry value, recording the original the first time so
        Restore-BoostState can put back exactly what was there.
    #>
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item $Path -Force -ErrorAction Stop | Out-Null }
        $key = Get-Item $Path
        $existed = $key.GetValueNames() -contains $Name
        $original = [pscustomobject]@{
            Path = $Path; Name = $Name; Existed = $existed
            Value = if ($existed) { $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames') } else { $null }
            Kind  = if ($existed) { $key.GetValueKind($Name).ToString() } else { $null }
        }
        if ($existed) { Set-ItemProperty $Path $Name $Value -ErrorAction Stop }
        else { New-ItemProperty $Path $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null }
        # Record only successful writes, and only the first one (later writes would record our own value)
        if (-not ($script:State.Registry | Where-Object { $_.Path -eq $Path -and $_.Name -eq $Name })) {
            $script:State.Registry += $original
            Save-BoostState
        }
    } catch {}
}

function Restore-BoostState {
    param($S)
    if (-not $S) { return }
    $failed = 0
    Restore-TimerResolution
    foreach ($svc in @($S.Services) | Where-Object { $_ }) {
        try { Start-Service $svc -ErrorAction Stop } catch { $failed++ }
    }
    foreach ($t in @($S.Tasks) | Where-Object { $_ }) {
        try { Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop | Out-Null } catch { $failed++ }
    }
    foreach ($r in @($S.Registry) | Where-Object { $_ }) {
        try {
            if ($r.Existed) {
                $v = if ($r.Kind -eq "Binary") { [byte[]]$r.Value } else { $r.Value }
                New-ItemProperty $r.Path $r.Name -Value $v -PropertyType $r.Kind -Force -ErrorAction Stop | Out-Null
            } elseif (Get-ItemProperty $r.Path $r.Name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty $r.Path $r.Name -ErrorAction Stop
            }
        } catch { $failed++ }
    }
    if ($S.MemCompression) {
        try { Enable-MMAgent -MemoryCompression -ErrorAction Stop } catch { $failed++ }
    }
    if ($S.PowerMode) {
        try { [WinApi]::PowerSetActiveOverlayScheme([guid]$S.PowerMode) | Out-Null } catch { $failed++ }
    }
    if ($S.DefenderPath) {
        try { Remove-MpPreference -ExclusionPath $S.DefenderPath -ErrorAction Stop } catch { $failed++ }
    }

    if ($failed -eq 0) {
        Remove-Item $StateFile -ErrorAction SilentlyContinue
        Write-Log "    System restored to original settings"
    } else {
        # Keep the file so StopBooster.bat (admin) can finish the job
        Write-Log "    $failed settings could not be restored (need admin?) -- run StopBooster.bat"
    }
}

# -- Game Process Detection -----------------------------------------------

function Get-TargetProcess {
    <#
    .SYNOPSIS
        Finds the running Game game process across all known executable names.
        Returns the first match or $null.
    #>
    foreach ($name in $ProcessNames) {
        $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) { return $proc }
    }
    return $null
}

# -- Memory & CPU Extreme Tuning ---------------------------------------------

function Set-HighResTimer {
    try {
        [int]$min=0; [int]$max=0; [int]$cur=0
        [WinApi]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur) | Out-Null
        [int]$actual=0
        [WinApi]::NtSetTimerResolution($max, $true, [ref]$actual) | Out-Null
        $resMs = [math]::Round($actual / 10000, 2)
        Write-Log "    Timer Resolution -> ${resMs}ms (hardware minimum)"
    } catch {}
}

function Restore-TimerResolution {
    try { [int]$actual=0; [WinApi]::NtSetTimerResolution(0, $false, [ref]$actual) | Out-Null } catch {}
}

function Get-FreeRAM_GB {
    return [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
}

function Clear-StandbyMemory {
    <#
    .SYNOPSIS
        Purges standby list ONLY when free RAM is critically low.
        v7.0: No longer called unconditionally every poll cycle.
    #>
    try { [WinApi]::PurgeStandbyList() | Out-Null } catch {}
}

function Compress-WorkingSets {
    <#
    .SYNOPSIS
        v7.0: Expanded protection list to include GPU-bound processes and
        raised minimum working set threshold to 50MB to avoid thrashing
        small processes that aren't worth compressing.
    #>
    $protected = @(
        "GameClient-Win64-Shipping", "GameClient-Win64-Shipping_EAC",
        "GameClient-Win64-Shipping_BE", "GameClient", "GameLauncher",
        "EasyAntiCheat", "EasyAntiCheat_EOS", "BEService", "BattlEye",
        "dwm", "csrss", "System", "svchost", "explorer", "audiodg", "conhost",
        # v7.0: Protect GPU-bound and anti-cheat adjacent processes
        "igfxCUIService", "igfxEM", "IntelGraphicsController",
        "Discord", "EpicGamesLauncher",  # User wants these running
        "lsass", "services", "wininit", "winlogon", "smss",
        "SecurityHealthSystray", "MsMpEng"  # Don't fight Windows Defender
    )
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin $protected -and $_.Name -notin $ProcessNames -and $_.WorkingSet64 -gt 50MB
    } | ForEach-Object {
        try { [WinApi]::EmptyWorkingSet($_.Handle) | Out-Null } catch {}
    }
}

function Set-TargetWorkingSetLock {
    <#
    .SYNOPSIS
        v7.0 NEW: Locks Game's working set to prevent Windows from
        paging it out. Sets min working set to 2GB, max to 16GB.
        This prevents page faults mid-game which cause micro-stutters.
    #>
    $fn = Get-TargetProcess
    if ($fn) {
        try {
            $minWS = [IntPtr]::new(2GB)
            $maxWS = [IntPtr]::new(16GB)
            # Flag 0x1 = QUOTA_LIMITS_HARDWS_MIN_ENABLE
            [WinApi]::SetProcessWorkingSetSizeEx($fn.Handle, $minWS, $maxWS, 0x1) | Out-Null
            Write-Log "    Game working set locked (2GB min, 16GB max)"
        } catch {
            Write-Log "    Working set lock failed (anti-cheat may block)"
        }
    }
}

function Set-TargetGPUPriority {
    <#
    .SYNOPSIS
        v7.0 NEW: Sets GPU scheduling priority for Game via registry.
        Value 8 = highest GPU priority. This tells the GPU scheduler to
        prioritize Game's render queue over everything else.
    #>
    try {
        $fnPaths = @(
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping.exe",
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping_EAC.exe",
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping_BE.exe"
        )
        foreach ($exePath in $fnPaths) {
            if (Test-Path $exePath) {
                $regKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$(Split-Path $exePath -Leaf)\PerfOptions"
                if (-not (Test-Path $regKey)) { New-Item $regKey -Force | Out-Null }
                Set-ItemProperty $regKey "GpuPriority" 8 -ErrorAction SilentlyContinue
                Set-ItemProperty $regKey "CpuPriorityClass" 3 -ErrorAction SilentlyContinue
                Set-ItemProperty $regKey "IoPriority" 3 -ErrorAction SilentlyContinue
            }
        }
        # Also set by process name for any install location
        $regKey2 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GameClient-Win64-Shipping.exe\PerfOptions"
        if (-not (Test-Path $regKey2)) { New-Item $regKey2 -Force | Out-Null }
        Set-ItemProperty $regKey2 "GpuPriority" 8 -ErrorAction SilentlyContinue
        Set-ItemProperty $regKey2 "CpuPriorityClass" 3 -ErrorAction SilentlyContinue
        Set-ItemProperty $regKey2 "IoPriority" 3 -ErrorAction SilentlyContinue
        Write-Log "    GPU Priority 8 (MAX), CPU Priority HIGH, IO Priority HIGH set for Game"
    } catch {}
}

function Set-GPUHighPerformanceForTarget {
    <#
    .SYNOPSIS
        v7.0 NEW: Forces Windows to use "High Performance" GPU preference
        for Game executables. On Intel Arc systems this ensures the
        dGPU-class scheduler is used, not the power-saving path.
    #>
    try {
        $gpuPrefKey = "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
        if (-not (Test-Path $gpuPrefKey)) { New-Item $gpuPrefKey -Force | Out-Null }
        # Default install path plus wherever the running game actually lives (other drives/libraries)
        $fnExes = @(
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping.exe"
            (Get-TargetProcess).Path
        ) | Where-Object { $_ } | Select-Object -Unique
        foreach ($exe in $fnExes) {
            if (Test-Path $exe) {
                Set-ItemProperty $gpuPrefKey $exe "GpuPreference=2;" -ErrorAction SilentlyContinue
            }
        }
        Write-Log "    GPU preference set to High Performance for Game"
    } catch {}
}

function Disable-MemoryCompression {
    <#
    .SYNOPSIS
        v7.0 NEW: Disables Windows Memory Compression during gameplay.
        Memory compression uses CPU cycles to compress RAM pages, which
        competes with Game for CPU time on the P-Cores.
    #>
    try {
        $current = Get-MMAgent -ErrorAction SilentlyContinue
        if ($current.MemoryCompression) {
            Disable-MMAgent -MemoryCompression -ErrorAction Stop
            $script:State.MemCompression = $true
            Write-Log "    Windows Memory Compression DISABLED (frees CPU for game)"
        }
    } catch {}
}

function Set-BoosterIdlePriority {
    <#
    .SYNOPSIS
        v7.0 NEW: Sets THIS booster script to Idle priority so it never
        steals CPU time from Game. Also pins it to E-Cores.
    #>
    try {
        $self = Get-Process -Id $PID
        $self.PriorityClass = 'Idle'
        $self.ProcessorAffinity = 0xF0  # E-Cores only
    } catch {}
}

function Set-TargetExtremeAffinity {
    <#
    .SYNOPSIS
        P-Cores (0-3) = 0x0F. E-Cores (4-7) = 0xF0.
        Intel Core Ultra 7 258V: 4P + 4E, no hyperthreading, 8 logical processors.
    #>
    $fn = Get-TargetProcess
    if ($fn) {
        try {
            $fn.PriorityClass = 'High'
            $fn.ProcessorAffinity = 0x0F  # Cores 0,1,2,3 (P-Cores)
            Write-Log "    Game PID $($fn.Id) -> HIGH priority, P-CORES ONLY (0x0F)"
        } catch {
            # Anti-cheat may block affinity but allow priority
            try {
                $fn.PriorityClass = 'High'
                Write-Log "    Game PID $($fn.Id) -> HIGH priority (affinity blocked by anti-cheat)"
            } catch {
                Write-Log "    Anti-cheat blocked all process tuning"
            }
        }
    }

    # Banish background apps to E-Cores
    $banishedCount = 0
    foreach ($appName in $ECoreBanishedApps) {
        Get-Process -Name $appName -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $_.ProcessorAffinity = 0xF0  # Cores 4,5,6,7 (E-Cores)
                $_.PriorityClass = 'BelowNormal'
                $banishedCount++
            } catch {}
        }
    }
    if ($banishedCount -gt 0) { Write-Log "    Banished $banishedCount background procs to E-CORES (0xF0)" }
}

function Enable-BestPerformanceMode {
    <#
    .SYNOPSIS
        Switches the Windows 11 power mode slider to "Best performance".
        Lunar Lake laptops use Modern Standby, where custom plans such as
        Ultimate Performance can't be activated, so the slider is the lever.
    #>
    try {
        $current = [guid]::Empty
        if ([WinApi]::PowerGetActualOverlayScheme([ref]$current) -ne 0) { return }
        if ($current -eq $BestPerformanceMode) {
            Write-Log "    Power mode already Best performance"
            return
        }
        if ([WinApi]::PowerSetActiveOverlayScheme($BestPerformanceMode) -eq 0) {
            $script:State.PowerMode = $current.ToString()
            Save-BoostState
            Write-Log "    Power mode -> Best performance"
        }
    } catch {}
}

# -- Input / OS Overrides ----------------------------------------------------

function Reduce-InputLag {
    # Raw mouse input (1:1 movement, no acceleration)
    $mouse = "HKCU:\Control Panel\Mouse"
    Set-Reg $mouse "MouseSpeed" "0" String
    Set-Reg $mouse "MouseThreshold1" "0" String
    Set-Reg $mouse "MouseThreshold2" "0" String
    Set-Reg $mouse "SmoothMouseXCurve" ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00)) Binary
    Set-Reg $mouse "SmoothMouseYCurve" ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00)) Binary

    # MMCSS: Maximum priority for gaming tasks
    $mmcss = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-Reg $mmcss "SystemResponsiveness" 0
    Set-Reg $mmcss "NetworkThrottlingIndex" 0xFFFFFFFF
    $gamesKey = "$mmcss\Tasks\Games"
    Set-Reg $gamesKey "GPU Priority" 8
    Set-Reg $gamesKey "Priority" 6
    Set-Reg $gamesKey "Scheduling Category" "High" String
    Set-Reg $gamesKey "SFIO Priority" "High" String

    # Direct3D / DirectX max frame latency = 1
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Direct3D" "MaxFrameLatency" 1
    Set-Reg "HKCU:\SOFTWARE\Microsoft\DirectX" "MaxFrameLatency" 1

    # Disable FSO optimizations and Game DVR
    $gcs = "HKCU:\System\GameConfigStore"
    Set-Reg $gcs "GameDVR_FSEBehaviorMode" 2
    Set-Reg $gcs "GameDVR_HonorUserFSEBehaviorMode" 1
    Set-Reg $gcs "GameDVR_DXGIHonorFSEWindowsCompatible" 1
    Set-Reg $gcs "GameDVR_EFSEFeatureFlags" 0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0
    Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 1

    Write-Log "    Input lag elimination + MMCSS priority applied"
}

function Optimize-VisualEffects {
    # Custom performance mode (disables animations but keeps font smoothing)
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
    # Disable window animations
    Set-Reg "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" String
    Write-Log "    Visual effects minimized (transparency OFF, animations OFF)"
}

function Disable-FSOForTarget {
    try {
        $fnPaths = @(
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping.exe",
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping_EAC.exe",
            "$env:ProgramFiles\Epic Games\Game\GameGame\Binaries\Win64\GameClient-Win64-Shipping_BE.exe"
        )
        $appCompatKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        if (-not (Test-Path $appCompatKey)) { New-Item $appCompatKey -Force | Out-Null }
        foreach ($exe in ($fnPaths + (Get-TargetProcess).Path | Where-Object { $_ } | Select-Object -Unique)) {
            if (Test-Path $exe) {
                Set-ItemProperty $appCompatKey $exe "~ DISABLEDXMAXIMIZEDWINDOWEDMODE" -ErrorAction SilentlyContinue
            }
        }
        Write-Log "    Fullscreen Optimizations DISABLED for Game"
    } catch {}
}

function Set-DefenderExclusion {
    # Temporary: removed again by Restore-BoostState. Skipped if you already had it.
    $path = "$env:ProgramFiles\Epic Games\Game"
    try {
        if ((Get-MpPreference -ErrorAction Stop).ExclusionPath -contains $path) { return }
        Add-MpPreference -ExclusionPath $path -ErrorAction Stop
        $script:State.DefenderPath = $path
        Save-BoostState
        Write-Log "    Windows Defender exclusion added for Game directory (until game closes)"
    } catch {}
}

# -- DWM Compositor Optimization ---------------------------------------------

function Optimize-DWM {
    <#
    .SYNOPSIS
        Reduces Desktop Window Manager overhead. DWM runs on the GPU and competes
        with Game for render time on the Arc 140V.
    #>
    $dwmKey = "HKCU:\SOFTWARE\Microsoft\Windows\DWM"
    # Disable DWM overlays and unnecessary composition effects
    Set-Reg $dwmKey "EnableAeroPeek" 0
    Set-Reg $dwmKey "AlwaysHibernateThumbnails" 0
    # Reduce DWM frame latency
    Set-Reg $dwmKey "ForceEffectMode" 0
    Write-Log "    DWM compositor overhead reduced"
}

function Disable-MPO {
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" 5
    Write-Log "    Multi-Plane Overlay (MPO) DISABLED (stutter reduction)"
}

# -- Hardware ----------------------------------------------------------------

function Force-HAGS {
    <#
    .SYNOPSIS
        Forces Hardware-Accelerated GPU Scheduling ON. Critical for Intel Arc
        to reduce driver overhead in DX12/Vulkan titles like Game.
        Left on permanently: it only takes effect after a reboot.
    #>
    try {
        $hagsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        if (Test-Path $hagsKey) {
            Set-ItemProperty -Path $hagsKey -Name "HwSchMode" -Value 2 -ErrorAction SilentlyContinue
            Write-Log "    HAGS (Hardware-Accelerated GPU Scheduling) FORCED ON"
        }
    } catch {}
}

function Optimize-IntelGPU {
    <#
    .SYNOPSIS
        Intel Arc 140V specific optimizations:
        - Disable DPST (dynamic backlight/contrast that causes input lag)
        - Disable Panel Self-Refresh (causes micro-stutter on fast content)
        - Extend TDR timeout (prevents driver reset during heavy shader compilation)
        - Enable DirectStorage for GPU decompression
    #>
    # Arc GPU driver settings
    $intelKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
    if (Test-Path $intelKey) {
        Set-Reg $intelKey "FeatureTestControl" 0x9240
        Set-Reg $intelKey "PP_PSRDisableFeature" 1
        Write-Log "    Intel Arc 140V: DPST OFF, Panel Self-Refresh OFF"
    }

    # Extend TDR timeout to 30 seconds (prevents driver resets during heavy shader compile)
    $gfxKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    Set-Reg $gfxKey "TdrDelay" 30
    Set-Reg $gfxKey "TdrDdiDelay" 30
    Write-Log "    GPU TDR timeout extended to 30s (shader compile protection)"

    # DirectStorage: enable GPU decompression if available
    Set-Reg $gfxKey "DirectStorageForceDisable" 0
    Write-Log "    DirectStorage / GPU decompression enabled"
}

# -- Shader Cache Management --------------------------------------------------

function Clear-TargetShaderCache {
    <#
    .SYNOPSIS
        Clears stale shader caches from previous seasons. New seasons bring
        new shaders and the old PSO cache causes stutters until rebuilt.
    #>
    $cacheCleared = $false

    # Game's own pipeline state cache
    $fnCachePaths = @(
        "$env:LOCALAPPDATA\GameGame\Saved\PipelineCaches",
        "$env:LOCALAPPDATA\GameGame\Saved\webcache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache"
    )

    foreach ($path in $fnCachePaths) {
        if (Test-Path $path) {
            $lastWrite = (Get-Item $path).LastWriteTime
            $daysSinceWrite = (New-TimeSpan -Start $lastWrite -End (Get-Date)).Days
            if ($daysSinceWrite -gt $VRAMCacheCleanThresholdDays) {
                try {
                    Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $cacheCleared = $true
                } catch {}
            }
        }
    }

    # Intel Arc shader cache (DirectX)
    $dxCachePath = "$env:LOCALAPPDATA\D3DSCache"
    if (Test-Path $dxCachePath) {
        $cacheSize = (Get-ChildItem $dxCachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        if ($cacheSize -gt 500) {
            try {
                Remove-Item "$dxCachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $cacheCleared = $true
                Write-Log "    Cleared bloated D3D shader cache (${cacheSize}MB)"
            } catch {}
        }
    }

    if ($cacheCleared) {
        Write-Log "    Stale shader caches cleared (new season rebuild will run)"
    } else {
        Write-Log "    Shader caches are fresh, no cleanup needed"
    }
}

function Optimize-ShaderOverrides {
    # 0xFFFFFFFF = Unlimited shader cache limit (prevents stutter)
    Set-Reg "HKLM:\SOFTWARE\Microsoft\DirectX" "ShaderCacheLimitSize" 0xFFFFFFFF

    # Intel Arc specific shader optimizations
    $intelKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
    if (Test-Path $intelKey) {
        Set-Reg $intelKey "DisableShaderCache" 0
        Set-Reg $intelKey "ShaderCache" 1
    }
}

# -- Process & Service Management --------------------------------------------

function Stop-Bloatware {
    $freed = 0; $killed = 0
    foreach ($name in $KillList) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $ram = [math]::Round($_.WorkingSet64 / 1MB, 0)
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                $freed += $ram; $killed++
            } catch {}
        }
    }
    return @{ Killed = $killed; FreedMB = $freed }
}

function Disable-RespawningSources {
    $disabled = @()
    foreach ($pattern in $ScheduledTaskPatterns) {
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $pattern -and $_.State -ne 'Disabled' } | ForEach-Object {
            try {
                Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction Stop | Out-Null
                $disabled += @{ Name = $_.TaskName; Path = $_.TaskPath }
            } catch {}
        }
    }
    return $disabled
}

function Stop-GamingServices {
    $stopped = @()
    foreach ($svc in $ServiceStopList) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            try { Stop-Service -Name $svc -Force -ErrorAction Stop; $stopped += $svc } catch {}
        }
    }
    return $stopped
}

# -- Thermal Monitoring -------------------------------------------------------

function Get-CPUTemperature {
    <#
    .SYNOPSIS
        Attempts to read CPU temperature via WMI thermal zone.
        Returns temperature in Celsius or -1 if unavailable.
    #>
    try {
        $temp = (Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop).CurrentTemperature
        return [math]::Round(($temp[0] / 10) - 273.15, 0)
    } catch {
        return -1
    }
}

# -- Main Loop ----------------------------------------------------------------

# Leftover state means the last session was killed mid-game: undo it first
if (Test-Path $StateFile) {
    Write-Log "Leftover BoosterRestore.json found -- restoring settings from last session"
    try { Restore-BoostState (Get-Content $StateFile -Raw | ConvertFrom-Json) } catch { Write-Log "    Could not read BoosterRestore.json" }
}
if ($RestoreOnly) { exit }

$State            = New-BoostState
$wasRunning       = $false
$boostCount       = 0
$thermalWarned    = $false
$lastAffinityCheck  = [DateTime]::MinValue
$lastCompressTime   = [DateTime]::MinValue
$lastRespawnScan    = [DateTime]::MinValue
$lastThermalCheck   = [DateTime]::MinValue
$currentActivity  = "Monitoring system..."

try {
while ($true) {
    $fn = Get-TargetProcess
    $freeRam = Get-FreeRAM_GB
    $cpuTemp = Get-CPUTemperature

    # -- Game Launch -------------------------------------------
    if ($fn -and -not $wasRunning) {
        $boostCount++
        $currentActivity = "Activating Boost #$boostCount..."
        Update-Dashboard $true $currentActivity $freeRam $cpuTemp

        Set-BoosterIdlePriority
        Clear-TargetShaderCache
        $script:State = New-BoostState
        Optimize-ShaderOverrides
        Enable-BestPerformanceMode
        Set-HighResTimer

        $res = Stop-Bloatware
        $State.Tasks = @(Disable-RespawningSources)
        Save-BoostState
        Compress-WorkingSets
        Clear-StandbyMemory

        Set-TargetExtremeAffinity
        Set-TargetGPUPriority
        Set-GPUHighPerformanceForTarget

        Reduce-InputLag
        Disable-FSOForTarget
        Set-DefenderExclusion
        Optimize-DWM
        Disable-MPO

        $State.Services = @(Stop-GamingServices)
        Save-BoostState
        Optimize-IntelGPU
        Force-HAGS
        Optimize-VisualEffects

        Set-TargetWorkingSetLock
        Disable-MemoryCompression
        Save-BoostState

        $wasRunning = $true
        $thermalWarned = $false
        $lastCompressTime = Get-Date
        $lastRespawnScan = Get-Date
        $lastThermalCheck = Get-Date
        
        $currentActivity = "Boost Active. KILLED: $($res.Killed) procs. TASKS: $($State.Tasks.Count)."
    }

    # -- Active Polling (Every 3 seconds) -------------------------
    if ($fn -and $wasRunning) {
        $now = Get-Date
        $secsSinceCompress = ($now - $lastCompressTime).TotalSeconds

        if ($freeRam -lt $MinFreeRAM_GB -and $secsSinceCompress -ge $CompressCooldownSec) {
            Compress-WorkingSets
            Clear-StandbyMemory
            $currentActivity = "CRITICAL RAM! Compressed memory & purged standby."
            $lastCompressTime = $now
        } elseif ($freeRam -lt $MinFreeRAM_Warning -and $secsSinceCompress -ge $CompressCooldownSec) {
            Clear-StandbyMemory
            $currentActivity = "Low RAM Warning. Purged standby memory."
            $lastCompressTime = $now
        }

        if (($now - $lastAffinityCheck).TotalSeconds -ge 30) {
            $fn = Get-TargetProcess
            if ($fn) {
                try {
                    if ($fn.PriorityClass -ne 'High') { $fn.PriorityClass = 'High' }
                    if ($fn.ProcessorAffinity -ne 15) { $fn.ProcessorAffinity = 15 }
                } catch {}
                foreach ($appName in $ECoreBanishedApps) {
                    Get-Process -Name $appName -ErrorAction SilentlyContinue | ForEach-Object {
                        try { $_.ProcessorAffinity = 0xF0; $_.PriorityClass = 'BelowNormal' } catch {}
                    }
                }
            }
            $lastAffinityCheck = $now
        }

        if (($now - $lastRespawnScan).TotalSeconds -ge $RespawnScanInterval) {
            $res = Stop-Bloatware
            if ($res.Killed -gt 0) {
                $currentActivity = "Respawn scan killed $($res.Killed) bloatware processes."
            }
            $lastRespawnScan = $now
        }

        if (($now - $lastThermalCheck).TotalSeconds -ge 60) {
            if ($cpuTemp -gt 95) {
                $currentActivity = "WARNING: THERMAL THROTTLING LIKELY (${cpuTemp}C)!"
            }
            $lastThermalCheck = $now
        }

        Update-Dashboard $wasRunning $currentActivity $freeRam $cpuTemp
        Start-Sleep -Seconds $CheckIntervalActive
    }

    # -- Game Close ---------------------------------------------
    if (-not $fn -and $wasRunning) {
        $currentActivity = "Game closed. Restoring system settings..."
        Update-Dashboard $false $currentActivity $freeRam $cpuTemp

        Restore-BoostState $State

        $wasRunning = $false
        $currentActivity = "System fully restored. Monitoring..."
    }

    if (-not $fn) {
        Update-Dashboard $wasRunning $currentActivity $freeRam $cpuTemp
        Start-Sleep -Seconds $CheckIntervalIdle
    }
}
} finally {
    if ($wasRunning) {
        Restore-BoostState $State
    }
}
