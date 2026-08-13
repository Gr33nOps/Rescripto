<#
.SYNOPSIS
  Builds the Rescripto debug APK and installs it on the running
  Rescripto_Test emulator, replacing any existing install.

.DESCRIPTION
  Requires start_test_device.ps1 to have been run first (a device must
  already show up in `adb devices`). Package id and main activity are read
  from the Android project rather than hard-coded.
#>

$ErrorActionPreference = "Stop"

$RepoRoot    = Resolve-Path "$PSScriptRoot\..\.."
$FlutterBin  = "D:\flutter\flutter\bin"
$AndroidHome = "D:\Android\Sdk"

$env:ANDROID_HOME     = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
$env:PATH = "$FlutterBin;$AndroidHome\platform-tools;$env:PATH"

$adb = "$AndroidHome\platform-tools\adb.exe"

$devices = & $adb devices | Select-String "device$"
if (-not $devices) {
    throw "No authorized device found. Run start_test_device.ps1 first."
}

Push-Location $RepoRoot
try {
    Write-Output "Building debug APK..."
    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk --debug failed (exit $LASTEXITCODE)." }

    $apk = "$RepoRoot\build\app\outputs\flutter-apk\app-debug.apk"
    if (-not (Test-Path $apk)) { throw "Built APK not found at $apk" }

    Write-Output "Installing $apk ..."
    & $adb install -r $apk
    if ($LASTEXITCODE -ne 0) { throw "adb install failed (exit $LASTEXITCODE)." }

    $package = "com.rescripto.rescripto"
    Write-Output "Launching $package ..."
    & $adb shell monkey -p $package -c android.intent.category.LAUNCHER 1 | Out-Null

    Start-Sleep -Seconds 3
    Write-Output ""
    Write-Output "Foreground activity:"
    & $adb shell dumpsys activity activities | Select-String "mResumedActivity"
}
finally {
    Pop-Location
}
