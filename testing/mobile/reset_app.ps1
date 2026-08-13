<#
.SYNOPSIS
  Resets Rescripto to a clean-install state on the test device: force-stops
  the app and clears its data (database, prefs, downloaded models, secure
  storage) without touching the emulator or Android itself.

.PARAMETER Relaunch
  If set, relaunches the app immediately after clearing data (useful for
  re-testing first-run/onboarding).
#>
param(
    [switch]$Relaunch
)

$ErrorActionPreference = "Stop"

$AndroidHome = "D:\Android\Sdk"
$adb         = "$AndroidHome\platform-tools\adb.exe"
$Package     = "com.rescripto.rescripto"

$devices = & $adb devices | Select-String "device$"
if (-not $devices) {
    throw "No authorized device found. Run start_test_device.ps1 first."
}

Write-Output "Force-stopping $Package ..."
& $adb shell am force-stop $Package

Write-Output "Clearing app data (database, prefs, downloaded models, secure storage) ..."
& $adb shell pm clear $Package

if ($Relaunch) {
    Write-Output "Relaunching ..."
    & $adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
}

Write-Output "Done. App is now in a fresh-install state."
