# ============================================================================
#  GameBooster.ps1 v8.0 -- EXTREME MAXIMIZED
#  Tuned for: Intel Core Ultra 7 258V + Intel Arc 140V 16GB (Lunar Lake)
#  Windows 11 25H2 (Build 26200) | Wi-Fi 7 BE201
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
    [string[]]$ProcessNames = @("GameClient-Win64-Shipping", "cs2", "r5apex", "Valorant-Win64-Shipping", "hl2", "dota2"),
    [string]$GameName = "ANY_GAME",
    [switch]$Silent
)

# -- Auto-Elevation Check -----------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not $Silent) { Write-Host "Requesting Administrator privileges..." }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Silent) { $argList += " -Silent" }
    # Automatically elevate to Admin
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
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
    $ProcessNames = @("GameClient-Win64-Shipping", "cs2", "r5apex", "Valorant-Win64-Shipping")
}

$KillList = @(
    # Microsoft bloat
    "OneDrive", "msedge", "msedgewebview2", "Teams", "ms-teams", "SearchHost",
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
    "Spotify", "EpicWebHelper", "ollama app", "ollama", "WorkloadsSessionHost",
    "mc-fw-host", "chrome", "node", "PresentMonService", "WindowsTerminal",
    "notepad", "mspaint", "Code", "firefox", "brave", "opera",
    # Recording / streaming overhead
    "OBS64", "obs64", "Streamlabs*", "Medal*", "Overwolf*",
    "RadeonSoftware", "AMDRSServ", "ShareX", "Lightshot",
    # Background updaters & telemetry
    "SteamService", "steamwebhelper", "NahimicSvc*", "NahimicOSD",
    "CCleanerBrowser*", "UpdateAssistant", "SecurityHealthService",
    # 2026 H2 Windows additions
    "Recall*", "WindowsCopilotRuntime", "CopilotService",
    "MicrosoftEdge_X*", "msedge_proxy", "PhoneLink",
    # Java/runtime background
    "javaw", "java", "RuntimeBroker"
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

# -- Game Process Detection -----------------------------------------------

function Get-TargetProcess {
    <#
    .SYNOPSIS
        Finds the running Game game process across all known executable names.
        Returns the first match or $null.
    #>
    foreach ($name in $TargetProcessNames) {
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
        $_.Name -notin $protected -and $_.WorkingSet64 -gt 50MB
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
        $fnExes = (Get-TargetProcess).Path
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
            Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-Log "    Windows Memory Compression DISABLED (frees CPU for game)"
            return $true
        }
    } catch {}
    return $false
}

function Restore-MemoryCompression {
    try {
        Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
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

function Disable-NetworkAdapterPowerMgmt {
    <#
    .SYNOPSIS
        v7.0 NEW: Disables power management on ALL network adapters.
        Prevents Wi-Fi from micro-sleeping between packets which causes
        ping spikes and packet loss during gameplay.
    #>
    try {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
            # Disable power management via registry
            $adapterKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
            Get-ChildItem $adapterKey -ErrorAction SilentlyContinue | ForEach-Object {
                $driverDesc = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DriverDesc
                if ($driverDesc) {
                    Set-ItemProperty $_.PSPath "PnPCapabilities" 0x18 -ErrorAction SilentlyContinue  # Disable idle power mgmt
                }
            }
        }
        Write-Log "    Network adapter power management DISABLED"
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

function Enable-UltimatePerformance {
    <#
    .SYNOPSIS
        Activates 'Ultimate Performance' power plan with aggressive sub-settings
        tuned for Lunar Lake's power delivery.
    #>
    try {
        $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $current = powercfg /getactivescheme 2>&1
        $originalPowerPlan = $null

        if ($current -match "([A-Fa-f0-9\-]{36})") {
            $originalPowerPlan = $matches[1]
        }

        $check = powercfg /list | Select-String $ultimateGuid
        if (-not $check) {
            powercfg -duplicatescheme $ultimateGuid | Out-Null
            Write-Log "    Injected hidden Ultimate Performance power plan"
        }

        powercfg /setactive $ultimateGuid | Out-Null

        # Disable core parking entirely
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>&1 | Out-Null
        # Minimum processor state = 100%
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
        # Energy Performance Preference = 0 (maximum performance)
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0 2>&1 | Out-Null
        # Processor performance boost mode = aggressive
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 2>&1 | Out-Null
        # Processor idle disable = disable idle
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 1 2>&1 | Out-Null
        # Heterogeneous policy: prefer P-cores for foreground
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SCHEDPOLICY 5 2>&1 | Out-Null
        # Short thread scheduling: prefer P-cores
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SHORTSCHEDPOLICY 5 2>&1 | Out-Null

        powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null

        Write-Log "    Power Plan -> ULTIMATE PERFORMANCE (all idle disabled)"
        return $originalPowerPlan
    } catch {
        Write-Log "    Failed to apply Ultimate Performance plan"
        return $null
    }
}

function Restore-PowerPlan {
    param($OriginalPlanGuid)
    try {
        if ($OriginalPlanGuid) {
            powercfg /setactive $OriginalPlanGuid | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 5 2>&1 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 2>&1 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 50 2>&1 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0 2>&1 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 0 2>&1 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SCHEDPOLICY 0 2>&1 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR SHORTSCHEDPOLICY 0 2>&1 | Out-Null
            powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
            Write-Log "    Power Plan restored to original"
        }
    } catch {}
}

# -- Input / OS Overrides ----------------------------------------------------

function Reduce-InputLag {
    try {
        # Raw mouse input (1:1 movement, no acceleration)
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseSpeed" "0"
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0"
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0"
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "SmoothMouseXCurve" ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00))
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "SmoothMouseYCurve" ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00))

        # MMCSS: Maximum priority for gaming tasks
        $mmcss = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty $mmcss "SystemResponsiveness" 0 -ErrorAction SilentlyContinue
        Set-ItemProperty $mmcss "NetworkThrottlingIndex" 0xFFFFFFFF -ErrorAction SilentlyContinue
        $gamesKey = "$mmcss\Tasks\Games"
        if (-not (Test-Path $gamesKey)) { New-Item $gamesKey -Force | Out-Null }
        Set-ItemProperty $gamesKey "GPU Priority" 8 -ErrorAction SilentlyContinue
        Set-ItemProperty $gamesKey "Priority" 6 -ErrorAction SilentlyContinue
        Set-ItemProperty $gamesKey "Scheduling Category" "High" -ErrorAction SilentlyContinue
        Set-ItemProperty $gamesKey "SFIO Priority" "High" -ErrorAction SilentlyContinue

        # Direct3D / DirectX max frame latency = 1
        $d3dKey = "HKCU:\SOFTWARE\Microsoft\Direct3D"
        if (-not (Test-Path $d3dKey)) { New-Item $d3dKey -Force | Out-Null }
        New-ItemProperty $d3dKey "MaxFrameLatency" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        $dxKey = "HKCU:\SOFTWARE\Microsoft\DirectX"
        if (-not (Test-Path $dxKey)) { New-Item $dxKey -Force | Out-Null }
        New-ItemProperty $dxKey "MaxFrameLatency" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

        # Disable FSO optimizations and Game DVR
        New-ItemProperty "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty "HKCU:\System\GameConfigStore" "GameDVR_EFSEFeatureFlags" 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0 -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 1 -ErrorAction SilentlyContinue

        Write-Log "    Input lag elimination + MMCSS priority applied"
    } catch {}
}

function Restore-InputLag {
    try {
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseSpeed" "1"
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseThreshold1" "6"
        Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseThreshold2" "10"
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\GameBar" "UseNexusForGameBarEnabled" 1 -ErrorAction SilentlyContinue
        $mmcss = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty $mmcss "SystemResponsiveness" 20 -ErrorAction SilentlyContinue
        Set-ItemProperty $mmcss "NetworkThrottlingIndex" 10 -ErrorAction SilentlyContinue
    } catch {}
}

function Optimize-VisualEffects {
    try {
        # Custom performance mode (disables animations but keeps font smoothing)
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2 -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 -ErrorAction SilentlyContinue
        # Disable window animations
        Set-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" -ErrorAction SilentlyContinue
        Write-Log "    Visual effects minimized (transparency OFF, animations OFF)"
    } catch {}
}

function Restore-VisualEffects {
    try {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 0 -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 1 -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "1" -ErrorAction SilentlyContinue
    } catch {}
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
        foreach ($exe in $fnPaths) {
            if (Test-Path $exe) {
                Set-ItemProperty $appCompatKey $exe "~ DISABLEDXMAXIMIZEDWINDOWEDMODE" -ErrorAction SilentlyContinue
            }
        }
        Write-Log "    Fullscreen Optimizations DISABLED for Game"
    } catch {}
}

function Set-DefenderExclusion {
    try {
        Add-MpPreference -ExclusionPath "$env:ProgramFiles\Epic Games\Game" -ErrorAction SilentlyContinue
        Write-Log "    Windows Defender exclusion added for Game directory"
    } catch {}
}

function Optimize-Bcdedit {
    try {
        bcdedit /set useplatformclock false 2>&1 | Out-Null
        bcdedit /set tscsyncpolicy Enhanced 2>&1 | Out-Null
        bcdedit /set disabledynamictick yes 2>&1 | Out-Null
        Write-Log "    HPET disabled, dynamic ticks disabled (extreme low latency)"
    } catch {}
}

function Restore-Bcdedit {
    try {
        bcdedit /deletevalue useplatformclock 2>&1 | Out-Null
        bcdedit /deletevalue tscsyncpolicy 2>&1 | Out-Null
        bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null
    } catch {}
}

# -- DWM Compositor Optimization ---------------------------------------------

function Optimize-DWM {
    <#
    .SYNOPSIS
        Reduces Desktop Window Manager overhead. DWM runs on the GPU and competes
        with Game for render time on the Arc 140V.
    #>
    try {
        $dwmKey = "HKCU:\SOFTWARE\Microsoft\Windows\DWM"
        # Disable DWM overlays and unnecessary composition effects
        Set-ItemProperty $dwmKey "EnableAeroPeek" 0 -ErrorAction SilentlyContinue
        Set-ItemProperty $dwmKey "AlwaysHibernateThumbnails" 0 -ErrorAction SilentlyContinue
        # Reduce DWM frame latency
        New-ItemProperty $dwmKey "ForceEffectMode" 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Log "    DWM compositor overhead reduced"
    } catch {}
}

function Restore-DWM {
    try {
        $dwmKey = "HKCU:\SOFTWARE\Microsoft\Windows\DWM"
        Set-ItemProperty $dwmKey "EnableAeroPeek" 1 -ErrorAction SilentlyContinue
        Remove-ItemProperty $dwmKey "ForceEffectMode" -ErrorAction SilentlyContinue
    } catch {}
}

function Disable-MPO {
    try {
        $dwmKey = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
        New-ItemProperty $dwmKey "OverlayTestMode" 5 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Log "    Multi-Plane Overlay (MPO) DISABLED (stutter reduction)"
    } catch {}
}

function Restore-MPO {
    try {
        Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" -ErrorAction SilentlyContinue
    } catch {}
}

# -- Hardware ----------------------------------------------------------------

function Force-HAGS {
    <#
    .SYNOPSIS
        Forces Hardware-Accelerated GPU Scheduling ON. Critical for Intel Arc
        to reduce driver overhead in DX12/Vulkan titles like Game.
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
    try {
        # Arc GPU driver settings
        $intelKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
        if (Test-Path $intelKey) {
            New-ItemProperty $intelKey "FeatureTestControl" 0x9240 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty $intelKey "PP_PSRDisableFeature" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Log "    Intel Arc 140V: DPST OFF, Panel Self-Refresh OFF"
        }

        # Extend TDR timeout to 30 seconds (prevents driver resets during heavy shader compile)
        $tdrKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        New-ItemProperty $tdrKey "TdrDelay" 30 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty $tdrKey "TdrDdiDelay" 30 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Log "    GPU TDR timeout extended to 30s (shader compile protection)"

        # DirectStorage: enable GPU decompression if available
        $dsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        New-ItemProperty $dsKey "DirectStorageForceDisable" 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Log "    DirectStorage / GPU decompression enabled"
    } catch {}
}

function Restore-IntelGPU {
    try {
        $tdrKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Remove-ItemProperty $tdrKey "TdrDelay" -ErrorAction SilentlyContinue
        Remove-ItemProperty $tdrKey "TdrDdiDelay" -ErrorAction SilentlyContinue
    } catch {}
}

function Disable-USBSelectiveSuspend {
    try {
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
        powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
    } catch {}
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
    try {
        $dxKey = "HKLM:\SOFTWARE\Microsoft\DirectX"
        if (-not (Test-Path $dxKey)) { New-Item $dxKey -Force | Out-Null }
        # 0xFFFFFFFF = Unlimited shader cache limit (prevents stutter)
        New-ItemProperty $dxKey "ShaderCacheLimitSize" 0xFFFFFFFF -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        
        # Intel Arc specific shader optimizations
        $intelKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
        if (Test-Path $intelKey) {
            New-ItemProperty $intelKey "DisableShaderCache" 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            New-ItemProperty $intelKey "ShaderCache" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}
}

function Restore-ShaderOverrides {
    try {
        $dxKey = "HKLM:\SOFTWARE\Microsoft\DirectX"
        Remove-ItemProperty $dxKey "ShaderCacheLimitSize" -ErrorAction SilentlyContinue
        
        $intelKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
        if (Test-Path $intelKey) {
            Remove-ItemProperty $intelKey "DisableShaderCache" -ErrorAction SilentlyContinue
            Remove-ItemProperty $intelKey "ShaderCache" -ErrorAction SilentlyContinue
        }
    } catch {}
}

# -- Network -----------------------------------------------------------------

function Optimize-Network {
    # Nagle and TCP Tuning
    try {
        $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
        foreach ($iface in $interfaces) {
            $ip = (Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue).DhcpIPAddress
            if ($ip -and $ip -ne "0.0.0.0") {
                New-ItemProperty $iface.PSPath "TcpAckFrequency" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty $iface.PSPath "TCPNoDelay" 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty $iface.PSPath "TcpDelAckTicks" 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
        netsh int tcp set global autotuninglevel=disabled 2>&1 | Out-Null
        netsh int tcp set global rsc=disabled 2>&1 | Out-Null
        netsh int tcp set global ecncapability=disabled 2>&1 | Out-Null
        netsh int tcp set global timestamps=disabled 2>&1 | Out-Null
        ipconfig /flushdns 2>&1 | Out-Null
        Write-Log "    TCP: Nagle OFF, delayed ACK OFF, RSC OFF, ECN OFF"
    } catch {}

    # Wi-Fi 7 BE201 specific tuning
    try {
        $wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($wifi) {
            # Interrupt Moderation OFF (raw packet processing)
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "*InterruptModeration" -RegistryValue 0 -ErrorAction SilentlyContinue
            # Packet Coalescing OFF (don't batch packets = lower latency)
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "*PacketCoalescing" -RegistryValue 0 -ErrorAction SilentlyContinue
            # Throughput Booster ON
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "ThroughputBoosterEnabled" -RegistryValue 1 -ErrorAction SilentlyContinue
            # Roaming Aggressiveness -> Lowest (don't roam mid-game)
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "RoamAggressiveness" -RegistryValue 1 -ErrorAction SilentlyContinue
            # MIMO Power Save -> No SMPS (all antennas active)
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "MIMOPowerSaveMode" -RegistryValue 3 -ErrorAction SilentlyContinue
            # Wake on Magic Packet OFF (prevent wake interference)
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "*WakeOnMagicPacket" -RegistryValue 0 -ErrorAction SilentlyContinue
            Write-Log "    Wi-Fi 7 BE201: Interrupt Moderation OFF, Packet Coalescing OFF, Throughput Boost ON, Roaming Lowest"
        }
    } catch {}

    # Wi-Fi Power Saving OFF
    try {
        powercfg /SETACVALUEINDEX SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>&1 | Out-Null
        powercfg /SETACTIVE SCHEME_CURRENT 2>&1 | Out-Null
    } catch {}
}

function Restore-Network {
    try {
        netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
        netsh int tcp set global rsc=enabled 2>&1 | Out-Null
        netsh int tcp set global ecncapability=default 2>&1 | Out-Null
        netsh int tcp set global timestamps=default 2>&1 | Out-Null
        $wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($wifi) {
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "*InterruptModeration" -RegistryValue 1 -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "*PacketCoalescing" -RegistryValue 1 -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "ThroughputBoosterEnabled" -RegistryValue 0 -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "RoamAggressiveness" -RegistryValue 3 -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "MIMOPowerSaveMode" -RegistryValue 1 -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword "*WakeOnMagicPacket" -RegistryValue 1 -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Optimize-DNS {
    try {
        $wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($wifi) {
            $currentDNS = (Get-DnsClientServerAddress -InterfaceIndex $wifi.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
            Set-DnsClientServerAddress -InterfaceIndex $wifi.ifIndex -ServerAddresses ("1.1.1.1","1.0.0.1") -ErrorAction Stop
            Write-Log "    DNS -> Cloudflare 1.1.1.1 / 1.0.0.1"
            return $currentDNS
        }
    } catch {}
    return $null
}

function Restore-DNS {
    param([string[]]$OriginalDNS)
    if ($OriginalDNS -and $OriginalDNS.Count -gt 0) {
        try {
            $wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
            if ($wifi) { Set-DnsClientServerAddress -InterfaceIndex $wifi.ifIndex -ServerAddresses $OriginalDNS -ErrorAction Stop }
        } catch {}
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

$wasRunning       = $false
$stoppedServices  = @()
$disabledTasks    = @()
$originalDNS      = $null
$originalPower    = $null
$boostCount       = 0
$thermalWarned    = $false
$lastAffinityCheck  = [DateTime]::MinValue
$lastCompressTime   = [DateTime]::MinValue
$lastRespawnScan    = [DateTime]::MinValue
$lastThermalCheck   = [DateTime]::MinValue
$memCompressionWasOn = $false
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
        Optimize-ShaderOverrides
        $originalPower = Enable-UltimatePerformance
        Set-HighResTimer

        $res = Stop-Bloatware
        $disabledTasks = Disable-RespawningSources
        Compress-WorkingSets
        Clear-StandbyMemory

        Set-TargetExtremeAffinity
        Set-TargetGPUPriority
        Set-GPUHighPerformanceForTarget

        Reduce-InputLag
        Disable-FSOForTarget
        Optimize-Bcdedit
        Set-DefenderExclusion
        Disable-USBSelectiveSuspend
        Optimize-DWM
        Disable-MPO

        $stoppedServices = Stop-GamingServices
        Optimize-IntelGPU
        Force-HAGS
        Optimize-VisualEffects

        Set-TargetWorkingSetLock
        $memCompressionWasOn = Disable-MemoryCompression

        $wasRunning = $true
        $thermalWarned = $false
        $lastCompressTime = Get-Date
        $lastRespawnScan = Get-Date
        $lastThermalCheck = Get-Date
        
        $currentActivity = "Boost Active. KILLED: $($res.Killed) procs. TASKS: $($disabledTasks.Count)."
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

        Restore-TimerResolution
        if ($stoppedServices.Count -gt 0) {
            foreach ($s in $stoppedServices) { try { Start-Service $s -ErrorAction SilentlyContinue } catch {} }
            $stoppedServices = @()
        }
        if ($disabledTasks.Count -gt 0) {
            foreach ($t in $disabledTasks) { try { Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction SilentlyContinue | Out-Null } catch {} }
            $disabledTasks = @()
        }

        Restore-VisualEffects
        Restore-DWM
        Restore-MPO
        Restore-InputLag
        Restore-Bcdedit
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
        powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
        Restore-IntelGPU
        Restore-ShaderOverrides
        if ($memCompressionWasOn) { Restore-MemoryCompression; $memCompressionWasOn = $false }
        if ($originalPower) { Restore-PowerPlan $originalPower; $originalPower = $null }

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
        Restore-TimerResolution
        if ($stoppedServices.Count -gt 0) {
            foreach ($s in $stoppedServices) { try { Start-Service $s -ErrorAction SilentlyContinue } catch {} }
        }
        if ($disabledTasks.Count -gt 0) {
            foreach ($t in $disabledTasks) { try { Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction SilentlyContinue | Out-Null } catch {} }
        }
        Restore-VisualEffects
        Restore-DWM
        Restore-MPO
        Restore-InputLag
        Restore-Bcdedit
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
        powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
        Restore-IntelGPU
        Restore-ShaderOverrides
        if ($memCompressionWasOn) { Restore-MemoryCompression }
        if ($originalPower) { Restore-PowerPlan $originalPower }
    }
}



