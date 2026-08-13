<#
.SYNOPSIS
  Boots the Rescripto_Test AVD (creating it first if it doesn't exist yet)
  and waits until Android has fully booted and adb reports it as an
  authorized device.

.DESCRIPTION
  Safe to re-run: if Rescripto_Test is already running, this just waits for
  boot completion and returns. Run this before build_and_install.ps1.
#>

$ErrorActionPreference = "Stop"

$AndroidHome = "D:\Android\Sdk"
$JavaHome    = "C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot"
$AvdName     = "Rescripto_Test"

$env:ANDROID_HOME     = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
$env:JAVA_HOME        = $JavaHome
$env:PATH = "$AndroidHome\cmdline-tools\latest\bin;$AndroidHome\platform-tools;$AndroidHome\emulator;$env:PATH"

$avdManager = "$AndroidHome\cmdline-tools\latest\bin\avdmanager.bat"
$emulator   = "$AndroidHome\emulator\emulator.exe"
$adb        = "$AndroidHome\platform-tools\adb.exe"

$existing = & $avdManager list avd 2>&1 | Select-String -SimpleMatch "Name: $AvdName"
if (-not $existing) {
    throw "AVD '$AvdName' does not exist. Create it first (see testing/mobile/README.md for the avdmanager create command)."
}

$running = & $adb devices | Select-String "emulator-"
if (-not $running) {
    Write-Output "Starting emulator '$AvdName'..."
    Start-Process -FilePath $emulator -ArgumentList @(
        "-avd", $AvdName,
        "-no-snapshot-save",
        "-netfast",
        "-no-boot-anim"
    ) -WindowStyle Minimized
} else {
    Write-Output "An emulator instance is already running."
}

Write-Output "Waiting for device to appear in 'adb devices'..."
& $adb wait-for-device

Write-Output "Waiting for full Android boot (sys.boot_completed)..."
$deadline = (Get-Date).AddMinutes(10)
$booted = $false
while ((Get-Date) -lt $deadline) {
    $prop = (& $adb shell getprop sys.boot_completed 2>$null).Trim()
    if ($prop -eq "1") { $booted = $true; break }
    Start-Sleep -Seconds 3
}

if (-not $booted) {
    throw "Emulator did not report sys.boot_completed=1 within 10 minutes."
}

# Unlock the keyguard and keep the screen on so UI automation isn't blocked
# by a lock screen or dimmed display between interactions.
& $adb shell input keyevent 82 | Out-Null
& $adb shell settings put system screen_off_timeout 1800000 | Out-Null

Write-Output ""
Write-Output "Device ready:"
& $adb devices
