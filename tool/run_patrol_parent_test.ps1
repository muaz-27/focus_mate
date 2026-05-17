# Runs parent_control Patrol test via adb (bypasses Gradle UTP on Windows paths with spaces).
param(
    [string]$Device = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Get-OrchestratorApkPath {
    param([string]$ProjectRoot)

    $cached = Get-ChildItem -Path "$env:USERPROFILE\.gradle\caches" -Recurse -Filter "orchestrator*.apk" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($cached) { return $cached.FullName }

    $built = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "orchestrator*.apk" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($built) { return $built.FullName }

    $localApk = Join-Path $ProjectRoot "build\orchestrator-1.5.1.apk"
    if (Test-Path $localApk) { return $localApk }

    $orchestratorUrl = "https://dl.google.com/dl/android/maven2/androidx/test/orchestrator/1.5.1/orchestrator-1.5.1.apk"
    Write-Host "Downloading AndroidX Test Orchestrator 1.5.1..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $localApk) | Out-Null
    Invoke-WebRequest -Uri $orchestratorUrl -OutFile $localApk -UseBasicParsing
    return $localApk
}

if (-not $Device) {
    $Device = (adb devices | Select-String "device$" | Select-Object -First 1) -replace "\s+device$", ""
    if (-not $Device) { throw "No Android device found. Connect a device or pass -Device <serial>." }
}

Write-Host "Device: $Device" -ForegroundColor Cyan
Write-Host "Building Patrol test APKs..." -ForegroundColor Cyan
patrol build android -t patrol_test/parent_control_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$AppApk = Join-Path $Root "build\app\outputs\apk\debug\app-debug.apk"
$TestApk = Join-Path $Root "build\app\outputs\apk\androidTest\debug\app-debug-androidTest.apk"
$OrchestratorApk = Get-OrchestratorApkPath -ProjectRoot $Root

Write-Host "Orchestrator: $OrchestratorApk" -ForegroundColor DarkGray
Write-Host "Installing APKs..." -ForegroundColor Cyan
adb -s $Device install -r -t -g $AppApk | Out-Host
adb -s $Device install -r -t -g $TestApk | Out-Host
adb -s $Device install -r -t -g $OrchestratorApk | Out-Host

Write-Host "Running tests via AndroidX Orchestrator (required by Patrol)..." -ForegroundColor Cyan
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
adb -s $Device shell am instrument -w -r `
    -e clearPackageData true `
    -e targetInstrumentation com.example.focus_mate.test/pl.leancode.patrol.PatrolJUnitRunner `
    androidx.test.orchestrator/androidx.test.orchestrator.AndroidTestOrchestrator
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "Test failed. Tips:" -ForegroundColor Yellow
    Write-Host "  - stretch_effect.frag: ensure theme uses InkRipple, then flutter clean + rerun" -ForegroundColor Yellow
    Write-Host "  - localhost:8082: app crashed before Patrol started; check logcat:" -ForegroundColor Yellow
    $logcatCmd = "adb -s $Device logcat -d -s flutter Patrol PatrolServer"
    Write-Host "    $logcatCmd" -ForegroundColor DarkGray
    exit $exitCode
}

Write-Host "All tests passed." -ForegroundColor Green
exit 0
