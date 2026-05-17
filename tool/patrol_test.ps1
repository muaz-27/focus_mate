# Wrapper for `patrol test` on Windows when the project path contains spaces.
# Gradle/UTP often fails with: "Failed to receive the UTP test results" / Total: 0
#
# Usage (from anywhere):
#   .\tool\patrol_test.ps1 -t patrol_test/parent_control_test.dart -d DEVICE_ID
#
# Or from project root:
#   powershell -File tool/patrol_test.ps1 -t patrol_test/parent_control_test.dart

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PatrolArgs
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Invoke-PatrolInRoot {
    param([string]$WorkingRoot)
    Set-Location $WorkingRoot

    $args = @($PatrolArgs)
    if ($args.Count -eq 0 -or $args[0] -ne 'test') {
        $args = @('test') + $args
    }

    # Patrol/Gradle write notes to stderr; do not treat them as terminating errors.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & patrol @args
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    return $code
}

if ($Root -notmatch '\s') {
    exit (Invoke-PatrolInRoot -WorkingRoot $Root)
}

$DriveLetter = $null
foreach ($letter in @('P', 'F', 'G', 'H', 'T')) {
    $candidate = "${letter}:"
    if (-not (Test-Path $candidate)) {
        $DriveLetter = $candidate
        break
    }
}

if (-not $DriveLetter) {
    throw "No free drive letter for SUBST. Close unused mapped drives or move the project to a path without spaces."
}

Write-Host "Mapping $DriveLetter -> $Root" -ForegroundColor Yellow
Write-Host "(Gradle UTP breaks when the project path contains spaces.)" -ForegroundColor DarkGray

subst $DriveLetter $Root
try {
    $exit = Invoke-PatrolInRoot -WorkingRoot "${DriveLetter}\"
    exit $exit
}
finally {
    subst $DriveLetter /d 2>$null | Out-Null
}
