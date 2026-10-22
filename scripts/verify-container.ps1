param([string]$Image = 'platform-delivery-lab:0.1.0')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(3)

function Invoke-Docker {
    param([string[]]$Arguments)
    # PowerShell 5.1 treats redirected native stderr as PowerShell errors.
    # Capture it without terminating, then check Docker's actual exit code.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nativeOutput = & docker @Arguments 2>&1
        $nativeExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    [pscustomobject]@{
        ExitCode = $nativeExit
        Output = (@($nativeOutput | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    }
}

function Assert-Response {
    param([string]$Url, [int]$ExpectedStatus, [hashtable]$ExpectedFields)
    $response = $client.GetAsync($Url).GetAwaiter().GetResult()
    try {
        $status = [int]$response.StatusCode
        if ($status -ne $ExpectedStatus) { throw "$Url returned $status, expected $ExpectedStatus" }
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        foreach ($key in $ExpectedFields.Keys) {
            if ($body.$key -ne $ExpectedFields[$key]) { throw "$Url returned unexpected field: $key" }
        }
        Write-Output "PASS $Url -> $status"
    }
    finally { $response.Dispose() }
}

try {
    foreach ($ready in @('true', 'false')) {
        $containerName = 'delivery-lab-check-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        $containerRef = $null
        $caseError = $null
        $cleanupError = $null
        try {
            # Retain the owned container until diagnostics are collected.
            # Separate creation also makes failed starts inspectable.
            $created = Invoke-Docker -Arguments @('create', '--name', $containerName, '--label', 'platform-delivery-lab.check=smoke', '--publish', '127.0.0.1::8080', '--read-only', '--tmpfs', '/tmp', '--env', 'APP_ENV=smoke', '--env', 'APP_VERSION=0.1.0-check', '--env', "APP_READY=$ready", $Image)
            if ($created.ExitCode -ne 0) { throw "Could not create verification container: $($created.Output)" }
            $containerRef = $containerName
            $startedContainer = Invoke-Docker -Arguments @('start', $containerRef)
            if ($startedContainer.ExitCode -ne 0) { throw "Could not start verification container: $($startedContainer.Output)" }
            $binding = Invoke-Docker -Arguments @('port', $containerRef, '8080/tcp')
            if ($binding.ExitCode -ne 0 -or -not $binding.Output) { throw "Could not identify published port: $($binding.Output)" }
            $baseUrl = 'http://' + ($binding.Output -split "`r?`n" | Select-Object -First 1).Trim()

            $started = $false
            $startupTimer = [System.Diagnostics.Stopwatch]::StartNew()
            while ($startupTimer.Elapsed.TotalSeconds -lt 15) {
                try {
                    $probe = $client.GetAsync("$baseUrl/healthz").GetAwaiter().GetResult()
                    $started = [int]$probe.StatusCode -eq 200
                    $probe.Dispose()
                }
                catch { $started = $false }
                if ($started) { break }
                $state = Invoke-Docker -Arguments @('inspect', '--format', '{{.State.Running}}', $containerRef)
                if ($state.ExitCode -ne 0) { throw "Could not inspect verification container: $($state.Output)" }
                if ($state.Output -ne 'true') { throw 'Application container exited before becoming reachable' }
                Start-Sleep -Milliseconds 300
            }
            if (-not $started) { throw 'Application did not become reachable within the startup deadline' }

            $uid = Invoke-Docker -Arguments @('exec', $containerRef, 'id', '-u')
            $gid = Invoke-Docker -Arguments @('exec', $containerRef, 'id', '-g')
            $readOnly = Invoke-Docker -Arguments @('inspect', '--format', '{{.HostConfig.ReadonlyRootfs}}', $containerRef)
            if ($uid.ExitCode -ne 0 -or $uid.Output -ne '10001') { throw 'Unexpected container user' }
            if ($gid.ExitCode -ne 0 -or $gid.Output -ne '10001') { throw 'Unexpected container group' }
            if ($readOnly.ExitCode -ne 0 -or $readOnly.Output -ne 'true') { throw 'Could not verify read-only root filesystem' }
            Write-Output "PASS APP_READY=$ready, uid=10001, gid=10001, read-only root filesystem"
            Assert-Response "$baseUrl/" 200 @{ service = 'platform-delivery-lab' }
            Assert-Response "$baseUrl/healthz" 200 @{ status = 'ok' }
            Assert-Response "$baseUrl/version" 200 @{ version = '0.1.0-check'; environment = 'smoke' }
            if ($ready -eq 'true') {
                Assert-Response "$baseUrl/readyz" 200 @{ status = 'ready' }
            }
            else {
                Assert-Response "$baseUrl/readyz" 503 @{ status = 'not_ready' }
            }

            $containerLogs = Invoke-Docker -Arguments @('logs', $containerRef)
            if ($containerLogs.ExitCode -ne 0) { throw "Could not read container logs: $($containerLogs.Output)" }
            if ($containerLogs.Output -match '\[(ERROR|CRITICAL)\]|Traceback \(most recent call last\)') {
                throw 'Application served requests but reported a runtime error in its logs'
            }
            Write-Output 'PASS no runtime errors found in container logs'
        }
        catch {
            $caseError = $_
            if ($containerRef) {
                try {
                    $diagnostics = Invoke-Docker -Arguments @('logs', $containerRef)
                    Write-Output "Container diagnostics for ${containerRef}:"
                    Write-Output $diagnostics.Output
                    if ($diagnostics.ExitCode -ne 0) { Write-Warning 'Docker could not retrieve application logs' }
                }
                catch { Write-Warning "Could not collect diagnostics: $($_.Exception.Message)" }
            }
        }
        finally {
            if ($containerRef) {
                try {
                    $stopped = Invoke-Docker -Arguments @('stop', '--timeout', '5', $containerRef)
                    if ($stopped.ExitCode -eq 0) {
                        $removed = Invoke-Docker -Arguments @('rm', $containerRef)
                    }
                    else {
                        $removed = Invoke-Docker -Arguments @('rm', '--force', $containerRef)
                    }
                    # Only a successful empty listing proves absence. An
                    # unavailable daemon must not be mistaken for cleanup.
                    $remaining = Invoke-Docker -Arguments @('container', 'ls', '--all', '--quiet', '--filter', "name=^/${containerRef}$")
                    if ($remaining.ExitCode -ne 0 -or $remaining.Output) {
                        $cleanupError = "Could not confirm removal of $containerRef. Removal: $($removed.Output). Check: $($remaining.Output)"
                    }
                }
                catch { $cleanupError = "Cleanup failed for ${containerRef}: $($_.Exception.Message)" }
            }
        }
        if ($caseError -and $cleanupError) { throw "$($caseError.Exception.Message) Cleanup also failed: $cleanupError" }
        if ($caseError) { throw $caseError }
        if ($cleanupError) { throw $cleanupError }
    }
    Write-Output 'Container verification passed; temporary containers removed.'
}
finally { $client.Dispose() }
