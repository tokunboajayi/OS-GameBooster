$p = "c:\Users\RecoveryAdmin\OneDrive\Documents\FORT SCRIPT\GameBooster\GameBooster.ps1"
$c = Get-Content $p -Raw

# Specific functions and names
$c = $c -creplace "FortniteBooster", "GameBooster"
$c = $c -creplace "Get-FortniteProcess", "Get-TargetProcess"
$c = $c -creplace "Clear-FortniteShaderCache", "Clear-TargetShaderCache"
$c = $c -creplace "Set-FortniteWorkingSetLock", "Set-TargetWorkingSetLock"
$c = $c -creplace "Set-FortniteGPUPriority", "Set-TargetGPUPriority"
$c = $c -creplace "Set-GPUHighPerformanceForFortnite", "Set-GPUHighPerformanceForTarget"
$c = $c -creplace "Disable-FSOForFortnite", "Disable-FSOForTarget"
$c = $c -creplace "Set-FortniteExtremeAffinity", "Set-TargetExtremeAffinity"

# UI and Variables
$c = $c -creplace "FORTNITE_CLIENT", "GAME_CLIENT"
$c = $c -creplace "FortniteProcessNames", "ProcessNames"
$c = $c -creplace "FortniteGameUserSettings", "TargetGameUserSettings"
$c = $c -creplace "FortniteLocalAppData", "TargetLocalAppData"

# Generic words
$c = $c -creplace "Fortnite", "Game"
$c = $c -creplace "fortnite", "game"

Set-Content $p $c
