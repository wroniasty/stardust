# Runs the project headless and then the smoke test, failing if Godot printed
# any error in either. Usage: powershell -File tools/check.ps1 [-Frames 120]
#
# The smoke test is scanned for engine errors too, not just for its own verdict.
# It used to report OK while Godot was printing "Can't change this state while
# flushing queries" underneath it: the assertions only know what they ask about,
# and an illegal call the engine merely complains about passes them all. The
# test exercises far more of the game than a 120 frame idle run does, so it is
# the better place to catch that class of bug.
param(
    [int]$Frames = 120,
    [string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pattern = "SCRIPT ERROR|SCRIPT-ERROR|Parse Error|ERROR:|Failed to load|Can't open|Can't change this state"

function Invoke-Stage {
    param([string]$Label, [string[]]$Arguments)

    Write-Host $Label
    # Continue, not Stop, around the native call: Godot writes warnings to
    # stderr, and with 2>&1 PowerShell turns every stderr line into a
    # terminating error. A harmless warning would abort the whole check.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $Godot @Arguments 2>&1 | Out-String
    $ErrorActionPreference = $previous
    Write-Host $output

    $bad = $output -split "`n" | Where-Object { $_ -match $pattern }
    if ($bad) {
        Write-Host "FAILED: errors during $Label" -ForegroundColor Red
        Write-Host ($bad -join "`n") -ForegroundColor Red
        exit 1
    }
    return $output
}

Write-Host "Importing assets..."
& $Godot --headless --path $root --import | Out-Null

Invoke-Stage "Running $Frames frames headless..." @("--headless", "--path", $root, "--quit-after", $Frames) | Out-Null

$smoke = Invoke-Stage "Running the smoke test..." @("--headless", "--path", $root, "--script", "res://tools/smoke_test.gd")
if ($smoke -notmatch "smoke test: OK") {
    Write-Host "FAILED: the smoke test did not report OK" -ForegroundColor Red
    exit 1
}

Write-Host "OK: no errors" -ForegroundColor Green
exit 0
