<#
.SYNOPSIS
  G1 local run wrapper: on a GPU-equipped Windows PC, drive the R1/R3 probe for all four
  rounds (window/fullscreen x 60/30fps) with one command, then verify each round.

.DESCRIPTION
  Wraps the collection steps from docs/qa/evidence/pc_win_02/README.md:
    1) Back up and temporarily point project.godot run/main_scene at probe_runner.tscn
       (required for the Godot editor/console binary; no-op if you pass an exported exe).
    2) For each of the four rounds, launch the binary NON-headless (GPU timing needs a real window).
    3) Redirect CSV output per round via --user-data-dir into a local, locatable directory.
    4) After all four rounds, run verify_probe_evidence.py on each (must print RESULT: PASS).
    5) Restore project.godot.

  Discipline (consistent with the probe and runbook):
    - The run target MUST be non-headless (headless has no GPU frame-capture chain -> 5 items blocked).
    - --build-sha MUST be the actual built commit SHA (or set PROBE_BUILD_SHA in the probe source).
    - The four rounds MUST NOT be mixed; each runs in its own process and is archived per round_id.

.EXAMPLE
  # Use the Godot editor/console binary directly (no separate export; build_type recorded as debug)
  .\tools\qa\run_g1_probe.ps1 -GodotExe "C:\Godot\Godot_v4.3-stable_win64_console.exe"

  # Use an already-exported release exe (probe baked in as main scene); explicit build_sha
  .\tools\qa\run_g1_probe.ps1 -GodotExe ".\builds\Hollowkin_probe.exe" -BuildSha "53d64c2"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExe,                                  # Path to Godot editor/console binary OR exported exe
    [string]$BuildSha = "",                             # Actual built SHA; blank => auto git rev-parse HEAD
    [string]$UserDir = "evidence\pc_win_02\userdata",   # CSV output root (relative to repo root)
    [int]$FrameSamples = 120,                           # Per-state / per-round frame samples
    [int]$WarmupFrames = 30,                            # Per-state warmup frames dropped
    [switch]$SkipVerify                                 # Skip verify_probe_evidence.py (not recommended)
)

$ErrorActionPreference = "Stop"
$repo = (Get-Location).Path

if ([string]::IsNullOrEmpty($BuildSha)) {
    $BuildSha = (git rev-parse HEAD).Trim()
}
Write-Host ("[G1] build_sha = {0}" -f $BuildSha) -ForegroundColor Cyan

$proj      = Join-Path $repo "project.godot"
$projBak   = Join-Path $repo "project.godot.bak_g1"
$probeScene = "res://src/qa/probe_runner.tscn"

# 1) Back up project.godot
Copy-Item $proj $projBak -Force

try {
    # 2) Temporarily set run/main_scene -> probe scene (needed for editor-binary mode;
    #    harmless for an exported exe that already baked the probe in).
    $txt = Get-Content $proj -Raw
    $txt = $txt -replace 'run/main_scene="[^"]*"', ('run/main_scene="' + $probeScene + '"')
    Set-Content $proj $txt -NoNewline
    Write-Host "[G1] project.godot main_scene -> probe_runner.tscn (backup: project.godot.bak_g1)" -ForegroundColor DarkGray

    # 3) Four rounds: window/fullscreen x 60/30fps
    $rounds = @(
        @{id = "windowed_60_release";   mode = "windowed";   fps = 60 },
        @{id = "windowed_30_release";   mode = "windowed";   fps = 30 },
        @{id = "fullscreen_60_release"; mode = "fullscreen"; fps = 60 },
        @{id = "fullscreen_30_release"; mode = "fullscreen"; fps = 30 }
    )

    $userFull = Join-Path $repo $UserDir
    New-Item -ItemType Directory -Force -Path $userFull | Out-Null

    foreach ($r in $rounds) {
        Write-Host ("[G1] === round {0}  mode={1}  fps={2} ===" -f $r.id, $r.mode, $r.fps) -ForegroundColor Yellow

        # Non-headless run: a real window is required to read GPU frame timings.
        & $GodotExe `
            --path $repo `
            --user-data-dir $userFull `
            --probe-auto `
            --round-id=$($r.id) `
            --window-mode=$($r.mode) `
            --fps-cap=$($r.fps) `
            --frame-samples=$FrameSamples `
            --warmup-frames=$WarmupFrames `
            --build-sha=$BuildSha

        if ($LASTEXITCODE -ne 0) {
            throw ("round {0} exited {1} (probe incomplete; see console PROBE_SUMMARY, fix and re-run this round)" -f $r.id, $LASTEXITCODE)
        }

        # Move this round's CSVs into a per-round_id subfolder (no cross-round mixing).
        $dest = Join-Path $userFull $r.id
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $m   = Join-Path $userFull ("hollowkin_probe_metrics_{0}.csv" -f $r.id)
        $raw = Join-Path $userFull ("hollowkin_probe_metrics_raw_{0}.csv" -f $r.id)
        if (Test-Path $m)   { Move-Item $m   $dest -Force }
        if (Test-Path $raw) { Move-Item $raw $dest -Force }

        # 4) Per-round verification
        if (-not $SkipVerify) {
            Write-Host ("[G1] verify {0}" -f $r.id) -ForegroundColor Yellow
            python tools/qa/verify_probe_evidence.py `
                (Join-Path $dest ("hollowkin_probe_metrics_{0}.csv" -f $r.id)) `
                (Join-Path $dest ("hollowkin_probe_metrics_raw_{0}.csv" -f $r.id))
            if ($LASTEXITCODE -ne 0) {
                Write-Warning ("verify {0} did NOT return PASS; inspect CSV and re-run this round" -f $r.id)
            }
        }
    }
}
finally {
    # 5) Restore project.godot (always, success or failure) to avoid polluting normal dev.
    if (Test-Path $projBak) {
        Move-Item $projBak $proj -Force
        Write-Host "[G1] project.godot restored (main_scene -> res://src/main.tscn)" -ForegroundColor Green
    }
}

Write-Host ("[G1] done. Four-round CSVs under {0}<round_id>\  (build_sha={1})" -f $userFull, $BuildSha) -ForegroundColor Green
Write-Host ("[G1] next: archive into pc_win_02/{0}/<round>/ per README §1 and back-fill governance §2.1" -f $BuildSha) -ForegroundColor Cyan
