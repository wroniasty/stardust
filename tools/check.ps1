# Runs the project headless for a few seconds and fails if Godot printed
# any script error. Usage: powershell -File tools/check.ps1 [-Frames 120]
param(
    [int]$Frames = 120,
    [string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Importing assets..."
& $Godot --headless --path $root --import | Out-Null

Write-Host "Running $Frames frames headless..."
$output = & $Godot --headless --path $root --quit-after $Frames 2>&1 | Out-String
Write-Host $output

$bad = $output -split "`n" | Where-Object {
    $_ -match "SCRIPT ERROR|SCRIPT-ERROR|Parse Error|ERROR:|Failed to load|Can't open"
}

if ($bad) {
    Write-Host "FAILED: errors in output" -ForegroundColor Red
    exit 1
}

Write-Host "OK: no errors" -ForegroundColor Green
exit 0
