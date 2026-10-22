param([string]$Image = 'platform-delivery-lab:0.1.0')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(3)

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
        $containerId = $null
        try {
            # Publish only on loopback, using a free host port selected by Docker.
            $containerId = docker run --detach --rm --name $containerName --label platform-delivery-lab.check=smoke --publish 127.0.0.1::8080 --read-only --tmpfs /tmp --env APP_ENV=smoke --env APP_VERSION=0.1.0-check --env "APP_READY=$ready" $Image
            if ($LASTEXITCODE -ne 0) { throw 'Could not start the verification container' }
            $binding = docker port $containerName 8080/tcp
            if ($LASTEXITCODE -ne 0 -or -not $binding) { throw 'Could not identify the published port' }
            $baseUrl = 'http://' + ($binding | Select-Object -First 1).Trim()

            $started = $false
            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                try {
                    $probe = $client.GetAsync("$baseUrl/healthz").GetAwaiter().GetResult()
                    $started = [int]$probe.StatusCode -eq 200
                    $probe.Dispose()
                }
                catch { $started = $false }
                if ($started) { break }
                Start-Sleep -Milliseconds 300
            }
            if (-not $started) {
                docker logs $containerName
                throw 'Application did not become reachable'
            }

            $containerUid = docker exec $containerName id -u
            if ($LASTEXITCODE -ne 0 -or $containerUid.Trim() -ne '10001') { throw 'Unexpected container user' }
            Write-Output "PASS APP_READY=$ready, user=10001, read-only filesystem"
            Assert-Response "$baseUrl/" 200 @{ service = 'platform-delivery-lab' }
            Assert-Response "$baseUrl/healthz" 200 @{ status = 'ok' }
            Assert-Response "$baseUrl/version" 200 @{ version = '0.1.0-check'; environment = 'smoke' }
            if ($ready -eq 'true') {
                Assert-Response "$baseUrl/readyz" 200 @{ status = 'ready' }
            }
            else {
                Assert-Response "$baseUrl/readyz" 503 @{ status = 'not_ready' }
            }

            $containerLogs = docker logs $containerName 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw 'Could not read container logs' }
            if ($containerLogs -match '\[(ERROR|CRITICAL)\]|Traceback \(most recent call last\)') {
                Write-Output $containerLogs
                throw 'Application served requests but reported a runtime error in its logs'
            }
            Write-Output 'PASS no runtime errors found in container logs'
        }
        finally {
            if ($containerId) {
                docker stop --time 5 $containerName | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-Warning "Check cleanup for container: $containerName" }
            }
        }
    }
    Write-Output 'Container verification passed; temporary containers stopped.'
}
finally { $client.Dispose() }
