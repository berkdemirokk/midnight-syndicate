# Local CI: the same steps as .github/workflows/ci.yml, on this machine.
# Usage (from the repo root):  powershell -ExecutionPolicy Bypass -File tools/ci_local.ps1
# Exit code 0 = everything passed.
# Continue: Godot writes expected error lines to stderr (corrupt-save tests); exit codes decide.
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$godot = if ($env:GODOT) { $env:GODOT } else { 'C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe' }
$logs = Join-Path $repo 'evidence\logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$fail = 0

Write-Host '== import'
& $godot --headless --path (Join-Path $repo 'game') --import *> (Join-Path $logs 'ci_import.log')
if (Select-String -Path (Join-Path $logs 'ci_import.log') -Pattern 'SCRIPT ERROR|Parse Error|SHADER ERROR' -Quiet) { Write-Host 'import: script/shader errors'; $fail = 1 }

Write-Host '== logic tests'
& $godot --headless --fixed-fps 60 --path (Join-Path $repo 'game') -s res://tests/run_tests.gd *> (Join-Path $logs 'ci_tests.log')
$testExit = $LASTEXITCODE
Get-Content (Join-Path $logs 'ci_tests.log') | Select-String -Pattern '^\[FAIL\]|^==' | ForEach-Object { $_.Line }
if ($testExit -ne 0) { $fail = 1 }

Write-Host '== asset validation'
& py -3.10 (Join-Path $repo 'tools\asset_factory.py') validate *> (Join-Path $logs 'ci_assets.log')
$assetExit = $LASTEXITCODE
Get-Content (Join-Path $logs 'ci_assets.log') -Tail 3
if ($assetExit -ne 0) { $fail = 1 }

if ($fail -eq 0) { Write-Host 'CI LOCAL: PASS' } else { Write-Host 'CI LOCAL: FAIL' }
exit $fail
