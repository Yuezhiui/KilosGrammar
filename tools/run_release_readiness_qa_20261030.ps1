param(
    [ValidateSet('catch','balloon','plane','calibration','routes','leaderboard','persistence','all')]
    [string] $Group = 'catch'
)

# Scoped regression launcher. Every Godot child process receives its own
# temporary APPDATA/LOCALAPPDATA tree. The existing app user:// and DB cannot
# be altered by a fixture writing a fixed test filename.
$ErrorActionPreference = 'Stop'
$godotExe = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportDir = Join-Path $projectRoot 'docs\release_readiness_20261030_logs'
$batchStamp = '{0}_{1}' -f $PID, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kilos_release_qa_worker12_' + $batchStamp)

$groups = [ordered]@{
    catch = @(
        'test_catch_character_editor_rig.gd',
        'test_catch_character_alignment.gd',
        'test_catch_new_character_alignment.gd',
        'test_catch_alpha_framing.gd',
        'test_catch_spawn_hud_safety.gd',
        'test_catch_three_apple_waves.gd',
        'test_catch_mode_speed_lock_20261029.gd'
    )
    balloon = @(
        'test_balloon_playable_window_20261030.gd',
        'test_balloon_wave_stress_20261030.gd',
        'test_balloon_shared_hud.gd',
        'test_balloon_continuous_20261030.gd',
        'test_balloon_mode_speed_lock_20261029.gd'
    )
    plane = @(
        'test_human_plane_continuous_integration.gd',
        'test_human_plane_body_integration.gd',
        'test_human_plane_ring_center_passage_20261029.gd',
        'test_human_plane_three_heart_hud.gd',
        'test_human_plane_mode_speed_lock_20261029.gd',
        'test_human_plane_solid_gate_handoff_20261029.gd'
    )
    calibration = @(
        'test_calibration_raw_bilateral_consumer_20261030.gd',
        'test_calibration_five_pose_png_sequences.gd',
        'test_calibration_independent_pose_guides.gd',
        'test_calibration_human_plane_center_only.gd',
        'test_calibration_cloned_voice_20261030.gd',
        'test_calibration_latency_retries.gd'
    )
    routes = @(
        'test_pause_hud_layers_20261030.gd',
        'test_pause_ready_escape_20261029.gd',
        'test_student_continue_gate_20261029.gd',
        'test_student_autofill_debounce_20261029.gd',
        'test_student_recovery_route_20261029.gd',
        'test_results_identity_stress_20261029.gd',
        'test_postgres_csv_delete_menu.gd'
    )
    leaderboard = @(
        'test_leaderboard_design.gd',
        'test_leaderboard_filter_pointer.gd',
        'test_leaderboard_oct24_visual.gd',
        'test_postgres_ui_integration.gd'
    )
    persistence = @(
        'test_play_score_retention_no_cleanup_stress.gd'
    )
}

New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $godotExe)) {
    throw ('Godot 4.7.2 binary unavailable: ' + $godotExe)
}

$chosen = @()
if ($Group -eq 'all') {
    foreach ($g in $groups.Keys) { $chosen += $groups[$g] }
}
else {
    $chosen = @($groups[$Group])
}
$results = @()
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
try {
    foreach ($scriptName in $chosen) {
        $caseId = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)
        # The pause/restart safety fixture explicitly requires a distinctive
        # disposable user:// root so it can never touch ordinary pupil data.
        $safeCaseId = if ($caseId -eq 'test_pause_ready_escape_20261029') {
            'kg_pause_worker21_' + $caseId
        } else { $caseId }
        $caseRoot = Join-Path $sandboxRoot $safeCaseId
        $stdout = Join-Path $reportDir ($caseId + '.stdout.log')
        $stderr = Join-Path $reportDir ($caseId + '.stderr.log')
        $env:APPDATA = Join-Path $caseRoot 'AppData'
        $env:LOCALAPPDATA = Join-Path $caseRoot 'LocalAppData'
        New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
        $start = [DateTime]::UtcNow
        # Use the .NET process API: Windows PowerShell 5's Start-Process
        # -PassThru with redirected streams can return an empty ExitCode
        # even after WaitForExit reports true.
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $godotExe
        $startInfo.Arguments = '--headless --path . --script res://tools/' + $scriptName
        $startInfo.WorkingDirectory = $projectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit(120000)
        if (-not $finished) {
            try { $process.Kill() } catch {}
            $process.WaitForExit()
        }
        $fullStdout = $stdoutTask.GetAwaiter().GetResult()
        $fullStderr = $stderrTask.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText($stdout, $fullStdout)
        [System.IO.File]::WriteAllText($stderr, $fullStderr)
        $durationMs = [int][Math]::Round(([DateTime]::UtcNow - $start).TotalMilliseconds)
        $rawOutput = $fullStdout + [Environment]::NewLine + $fullStderr
        $testPassed = $finished -and $process.ExitCode -eq 0
        # Some older tests log FAIL but still exit success: explicitly count
        # true failure markers; warnings and intentionally tested invalid
        # identity cases are reviewed from full per-case logs.
        $failureLines = @($rawOutput -split '[\r\n]+' | Where-Object {
            $_ -match '(^FAIL\b|^QA_FAIL\b|^.*FAIL CATEGORY:|^.*Assertion failed:|^.*SCRIPT ERROR:)'
        })
        if ($failureLines.Count -gt 0) { $testPassed = $false }
        $digest = @($rawOutput -split '[\r\n]+' | Where-Object {
            $_ -match '(?i)^(PASS\b|FAIL\b|QA_FAIL\b|.*QA: (PASS|FAIL)|.*checks.*failures.*)'
        } | Select-Object -Last 5) -join ' | '
        $entry = [pscustomobject]@{
            Test = $scriptName
            Group = $Group
            Status = if (-not $finished) { 'TIMEOUT' } elseif ($testPassed) { 'PASS' } else { 'FAIL' }
            ExitCode = if ($finished) { $process.ExitCode } else { -1 }
            DurationMs = $durationMs
            FailureLines = $failureLines.Count
            Digest = $digest
            Stdout = $stdout
            Stderr = $stderr
            UserSandbox = $caseRoot
        }
        $results += $entry
        Write-Output ('QA_RESULT {0} {1} exit={2} ms={3} fail_lines={4}' -f $entry.Status,$caseId,$entry.ExitCode,$durationMs,$entry.FailureLines)
        if ($digest.Length -gt 0) { Write-Output ('QA_DETAIL ' + $digest.Substring(0,[Math]::Min(480,$digest.Length))) }
    }
}
finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
}

$csv = Join-Path $reportDir ('results_' + $Group + '.csv')
$results | Export-Csv -Path $csv -Encoding UTF8 -NoTypeInformation
$passed = @($results | Where-Object Status -eq 'PASS').Count
$failed = @($results | Where-Object Status -ne 'PASS').Count
Write-Output ('QA_BATCH {0} pass={1} fail={2} total={3} csv={4}' -f $Group,$passed,$failed,$results.Count,$csv)
if ($failed -gt 0) { exit 1 }
exit 0
