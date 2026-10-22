$ErrorActionPreference = 'Stop'
$global:taskFixProbeDocker = (Get-Command docker.exe).Source
$global:taskFixProbeIds = New-Object 'System.Collections.Generic.List[string]'
$global:taskFixProbeMode = ''

function docker {
    $taskArguments = @($args)
    if ($taskArguments[0] -eq 'stop' -and $global:taskFixProbeMode -in @('StopFails', 'RemovalFails', 'BothFail')) {
        $global:LASTEXITCODE = 1
        return 'injected stop failure'
    }
    if ($taskArguments[0] -eq 'rm' -and $global:taskFixProbeMode -in @('RemovalFails', 'BothFail')) {
        $global:LASTEXITCODE = 1
        return 'injected removal failure'
    }
    if ($taskArguments[0] -eq 'container' -and $global:taskFixProbeMode -eq 'ListingFails') {
        $global:LASTEXITCODE = 1
        return 'injected daemon-listing failure'
    }
    if ($taskArguments[0] -eq 'create' -and $global:taskFixProbeMode -in @('StartupFails', 'BothFail')) {
        for ($taskIndex = 0; $taskIndex -lt $taskArguments.Count; $taskIndex++) {
            if ($taskArguments[$taskIndex] -eq 'APP_READY=true') { $taskArguments[$taskIndex] = 'APP_READY=invalid' }
        }
    }
    $taskNativeOutput = & $global:taskFixProbeDocker @taskArguments
    $taskNativeExit = $LASTEXITCODE
    if ($taskArguments[0] -eq 'create' -and $taskNativeExit -eq 0) {
        foreach ($taskLine in @($taskNativeOutput)) {
            if ($taskLine -match '^[0-9a-f]{64}$') { $global:taskFixProbeIds.Add($taskLine) }
        }
    }
    $global:LASTEXITCODE = $taskNativeExit
    $taskNativeOutput
}

foreach ($taskMode in @('StopFails', 'RemovalFails', 'ListingFails', 'StartupFails', 'BothFail')) {
    $global:taskFixProbeMode = $taskMode
    $global:taskFixProbeIds.Clear()
    $taskOutput = New-Object 'System.Collections.Generic.List[string]'
    $taskError = $null
    try {
        try {
            & (Join-Path $PSScriptRoot '..\..\scripts\verify-container.ps1') *>&1 | ForEach-Object { $taskOutput.Add($_.ToString()) }
        }
        catch { $taskError = $_ }
        $taskText = $taskOutput -join "`n"
        $taskSuccess = $taskText.Contains('Container verification passed; temporary containers removed.')
        $taskLogs = $taskText.Contains('APP_READY must be true or false')
        $taskCombined = $taskError -and $taskError.Exception.Message.Contains('Cleanup also failed:')
        if ($taskMode -eq 'StopFails') {
            if ($taskError -or -not $taskSuccess) { throw 'Forced-removal fallback did not succeed' }
        }
        else {
            if (-not $taskError -or $taskSuccess) { throw "Failure was incorrectly accepted: $taskMode" }
        }
        if ($taskMode -in @('StartupFails', 'BothFail') -and -not $taskLogs) { throw 'Startup error logs were lost' }
        if ($taskMode -eq 'BothFail' -and -not $taskCombined) { throw 'Primary error or cleanup error was lost' }
        [pscustomobject]@{Mode=$taskMode;Threw=[bool]$taskError;SuccessMessage=$taskSuccess;StartupLogsRetained=$taskLogs;CombinedError=[bool]$taskCombined} | ConvertTo-Json -Compress
    }
    finally {
        foreach ($taskId in $global:taskFixProbeIds) {
            $taskRemaining = & $global:taskFixProbeDocker container ls --all --quiet --no-trunc --filter "id=$taskId"
            if ($LASTEXITCODE -ne 0) { throw "Probe could not check its container: $taskId" }
            if ($taskRemaining) {
                & $global:taskFixProbeDocker rm --force $taskId | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Probe could not remove its container: $taskId" }
            }
        }
    }
}
Write-Output 'All five failure-path probes passed; probe containers removed.'
