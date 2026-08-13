<#
.SYNOPSIS
  Dumps a timestamped logcat snapshot filtered to what matters for
  Rescripto QA: Flutter/Dart exceptions, Android crashes/ANRs, permission
  denials, and the app's own process — into testing/mobile/logs/.

.PARAMETER Follow
  If set, streams logcat live (Ctrl+C to stop) instead of taking a
  point-in-time dump. Still writes to the same timestamped file.
#>
param(
    [switch]$Follow
)

$ErrorActionPreference = "Stop"

$RepoRoot    = Resolve-Path "$PSScriptRoot\..\.."
$AndroidHome = "D:\Android\Sdk"
$adb         = "$AndroidHome\platform-tools\adb.exe"
$Package     = "com.rescripto.rescripto"

$devices = & $adb devices | Select-String "device$"
if (-not $devices) {
    throw "No authorized device found. Run start_test_device.ps1 first."
}

$logDir = "$RepoRoot\testing\mobile\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = "$logDir\logcat_$stamp.txt"

$pid_ = (& $adb shell pidof $Package 2>$null).Trim()
Write-Output "Package: $Package  PID: $(if ($pid_) { $pid_ } else { '(not running)' })"
Write-Output "Writing to: $outFile"

# Broad but relevant: the app's own tag, Flutter's runtime, and the classic
# crash/ANR/permission sources. -v threadtime keeps timestamps for later
# correlation with screenshots.
$filterSpec = @(
    "flutter:V",
    "AndroidRuntime:E",
    "System.err:W",
    "ActivityManager:W",
    "WindowManager:W",
    "PackageManager:W",
    "*:S"
)

if ($Follow) {
    & $adb logcat -v threadtime @filterSpec | Tee-Object -FilePath $outFile
} else {
    & $adb logcat -v threadtime -d @filterSpec > $outFile
    Write-Output ""
    Write-Output "--- Crash/ANR/exception lines in this dump ---"
    Select-String -Path $outFile -Pattern "FATAL EXCEPTION|ANR in|AndroidRuntime|Exception|PlatformException|MissingPluginException" -ErrorAction SilentlyContinue
    Write-Output ""
    Write-Output "Full dump saved to $outFile"
}
