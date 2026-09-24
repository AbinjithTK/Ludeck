# env.ps1 — dot-source this before any Gradle command:  . .\scripts\env.ps1
#
# Why this file exists: `java` on PATH resolves to a dead Oracle stub
# (C:\ProgramData\Oracle\Java\javapath\java.exe, which does not exist), and
# Android Studio's bundled jbr is stripped (jbr\bin contains no executables).
# The working JDK is the one Gradle provisioned for itself. Verified 2026-09-20:
# openjdk 17.0.19, Temurin-17.0.19+10, javac present.

$env:JAVA_HOME = "$env:USERPROFILE\.gradle\jdks\eclipse_adoptium-17-amd64-windows.2"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

if (-not (Test-Path "$env:JAVA_HOME\bin\javac.exe")) {
    Write-Host "JDK missing at $env:JAVA_HOME" -ForegroundColor Red
    Write-Host "Install one with: winget install EclipseAdoptium.Temurin.17.JDK" -ForegroundColor Yellow
    return
}
if (-not (Test-Path "$env:ANDROID_HOME\platforms")) {
    Write-Host "Android SDK platforms missing at $env:ANDROID_HOME" -ForegroundColor Red
    return
}

# platform-tools was EMPTY on this machine, so there is no adb. Without it you
# cannot install a build from the command line; Android Studio's Run button
# still works. To fix:
#   & "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" "platform-tools"
if (-not (Test-Path "$env:ANDROID_HOME\platform-tools\adb.exe")) {
    Write-Host "adb missing. Install with:" -ForegroundColor Yellow
    Write-Host "  & `"$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat`" platform-tools" -ForegroundColor Yellow
}

Write-Host "JAVA_HOME    $env:JAVA_HOME" -ForegroundColor Green
Write-Host "ANDROID_HOME $env:ANDROID_HOME" -ForegroundColor Green
