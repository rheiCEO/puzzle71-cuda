# Lokalny start: multi-GPU random (prefiks 74) + dashboard + Telegram
# Użycie: .\local-start.ps1
# Wymaga: bin\puzzle71-cuda.exe (build.bat) lub bin\puzzle71-cuda (Linux)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$env:START_HEX = if ($env:START_HEX) { $env:START_HEX } else { "740000000000000000" }
$env:END_HEX   = if ($env:END_HEX)   { $env:END_HEX }   else { "74ffffffffffffffff" }
$env:WORK_SCALE = if ($env:WORK_SCALE) { $env:WORK_SCALE } else { "16" }
$env:TELEGRAM_PROGRESS_EVERY_MLD = if ($env:TELEGRAM_PROGRESS_EVERY_MLD) { $env:TELEGRAM_PROGRESS_EVERY_MLD } else { "10000" }
$WatchPort = if ($env:WATCH_PORT) { $env:WATCH_PORT } else { "8768" }

New-Item -ItemType Directory -Force -Path "$Root\logs" | Out-Null

if (-not (Test-Path "$Root\bin\puzzle71-cuda.exe") -and -not (Test-Path "$Root\bin\puzzle71-cuda")) {
    Write-Host "Brak binarki — uruchom build.bat (Windows) lub bash scripts/build.sh (Linux/WSL)"
    exit 1
}

if (-not (Test-Path "$Root\telegram.env")) {
    Write-Host "UWAGA: brak telegram.env — skopiuj z telegram.env.example"
}

Write-Host "==> puzzle71-cuda LOCAL — prefiks 74"
Write-Host "    zakres: $($env:START_HEX) .. $($env:END_HEX)"

# Dashboard
Get-Process python* -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match "watch_multi.py"
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process python -ArgumentList @("$Root\watch_multi.py", "--bind", "127.0.0.1", "--port", $WatchPort, "--no-browser") `
    -WindowStyle Hidden -RedirectStandardOutput "$Root\logs\watch.log" -RedirectStandardError "$Root\logs\watch.err"

Start-Sleep -Seconds 2
Write-Host "    dashboard: http://127.0.0.1:$WatchPort/"

# Telegram watch
if ((Test-Path "$Root\telegram.env") -or $env:TELEGRAM_BOT_TOKEN) {
    python "$Root\telegram_notify.py" --test
    Start-Process python -ArgumentList @("$Root\telegram_notify.py", "--watch") `
        -WindowStyle Hidden -RedirectStandardOutput "$Root\logs\telegram.log" -RedirectStandardError "$Root\logs\telegram.err"
    Write-Host "    Telegram: ON (tail logs\telegram.log)"
} else {
    Write-Host "    Telegram: OFF"
}

# GPU — przez bash jeśli WSL/Git Bash, inaczej pojedynczy proces Windows
if (Get-Command bash -ErrorAction SilentlyContinue) {
    bash "$Root/scripts/run-all-gpus-random.sh"
} else {
    $bin = if (Test-Path "$Root\bin\puzzle71-cuda.exe") { "$Root\bin\puzzle71-cuda.exe" } else { "$Root\bin\puzzle71-cuda" }
    Write-Host "==> 1 GPU (brak bash) — tryb random"
    & $bin --mode random --start $env:START_HEX --end $env:END_HEX --work-scale $env:WORK_SCALE
}
