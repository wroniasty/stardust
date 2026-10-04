# Runs the project headless and then the smoke test, failing if Godot printed
# any error in either.
#   powershell -File tools/check.ps1 [-Frames 120] [-ImportTimeout 25]
#
# The smoke test is scanned for engine errors too, not just for its own verdict.
# It used to report OK while Godot was printing "Can't change this state while
# flushing queries" underneath it: the assertions only know what they ask about,
# and an illegal call the engine merely complains about passes them all. The
# test exercises far more of the game than a 120 frame idle run does, so it is
# the better place to catch that class of bug.
param(
    [int]$Frames = 120,
    [int]$ImportTimeout = 25,
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

# Bounded, and killed if it overruns.
#
# `--import` runs the editor, and a headless editor does not quit if the
# saved session has a script open: `.godot/editor/editor_layout.cfg`
# carries `open_scripts`, the script editor tries to restore itself with
# no window to restore into, and the process sits at zero per cent CPU
# for ever. Measured at 430 seconds before it was killed by hand, with
# the 120 frame stage that follows it taking 1.7. Scenes and shaders in
# the same file are harmless; only scripts do it.
#
# The work finishes long before the editor fails to shut down -- the
# class cache is on disk by then -- so overrunning is survivable and the
# right answer is to take the result and move on rather than to wait.
# The timeout is short for the same reason: a real import of this
# project takes three seconds, ten when it has work to do.
#
# The file is left alone. Editing somebody's editor session to suit a
# build script is the kind of help nobody asked for, so this says what
# is wrong and how to stop paying for it instead.
Write-Host "Importing assets..."
$layout = Join-Path $root ".godot\editor\editor_layout.cfg"
if ((Test-Path $layout) -and ((Get-Content $layout -Raw) -match 'open_scripts=\[[^\]]')) {
    Write-Host "  a script is open in the editor session, so the import will not quit on its own." -ForegroundColor Yellow
    Write-Host "  close the script tabs, or delete .godot/editor/editor_layout.cfg, to skip the wait." -ForegroundColor Yellow
}
$import = Start-Process -FilePath $Godot -PassThru -NoNewWindow -ArgumentList @(
    "--headless", "--path", $root, "--import"
)
if (-not $import.WaitForExit($ImportTimeout * 1000)) {
    Write-Host ("  import did not return in {0}s; its work is done, stopping it" -f $ImportTimeout) -ForegroundColor Yellow
    Stop-Process -Id $import.Id -Force -ErrorAction SilentlyContinue
    $import.WaitForExit(5000) | Out-Null
}

Invoke-Stage "Running $Frames frames headless..." @("--headless", "--path", $root, "--quit-after", $Frames) | Out-Null

$smoke = Invoke-Stage "Running the smoke test..." @("--headless", "--path", $root, "--script", "res://tools/smoke_test.gd")
if ($smoke -notmatch "smoke test: OK") {
    Write-Host "FAILED: the smoke test did not report OK" -ForegroundColor Red
    exit 1
}

Write-Host "OK: no errors" -ForegroundColor Green
exit 0
