#requires -Version 7.0
param([switch]$RunFailureExercise)

$ErrorActionPreference = 'Stop'
if (-not $RunFailureExercise) { throw 'Pass -RunFailureExercise to run the intentional failure in lab-release.' }
$root = Split-Path $PSScriptRoot -Parent
$extension = if ($IsWindows) { '.exe' } else { '' }
$helm = Join-Path $root "work/tools/helm$extension"
$kubectl = Join-Path $root "work/tools/kubectl$extension"
$kind = Join-Path $root "work/tools/kind$extension"
$kubeconfig = Join-Path $root 'work/kubeconfig'
$namespace = 'lab-release'
$context = 'kind-platform-delivery-lab'
$chart = Join-Path $root 'charts/delivery-lab'
$evidencePath = Join-Path $root 'work/releases/exercise-result.json'
$timeline = [Collections.Generic.List[object]]::new()
$knownGoodRevision = $null
$rollbackRequired = $false
$result = [ordered]@{ success = $false; startedUtc = [DateTime]::UtcNow.ToString('o'); timeline = $timeline }

function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    $output = & $Command @Arguments 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}
function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    $native = Invoke-Native $Command $Arguments
    if ($native.ExitCode -ne 0) { throw "$Command failed ($($native.ExitCode)): $($native.Output)" }
    $native.Output
}
function Invoke-LabKubectl {
    param([string[]]$Arguments)
    Invoke-Checked $kubectl (@('--kubeconfig', $kubeconfig, '--context', $context, '-n', $namespace) + $Arguments)
}
function Invoke-LabHelm {
    param([string[]]$Arguments)
    Invoke-Checked $helm (@('--kubeconfig', $kubeconfig, '--kube-context', $context, '--namespace', $namespace) + $Arguments)
}
function Record-Phase {
    param([string]$Name, [object]$Details)
    $timeline.Add([ordered]@{ phase = $Name; utc = [DateTime]::UtcNow.ToString('o'); details = $Details })
    Write-Output "PASS $Name"
}
function Deploy-Version {
    param([string]$Tag, [string]$Version)
    Invoke-LabHelm @('upgrade', '--install', 'delivery-lab', $chart, '-f', (Join-Path $chart 'values-staging.yaml'),
        '--set-string', "image.tag=$Tag", '--set-string', "app.version=$Version",
        '--set', 'app.ready=true', '--set', 'image.pullPolicy=Never', '--wait', '--timeout', '120s') | Write-Output
}
function Assert-Service {
    param([string]$Pod, [string]$Version, [string]$CachePolicy)
    $check = @'
import json, sys, urllib.request
version, cache_policy = sys.argv[1:]
for index in range(12):
    for path, expected in [("/version", {"version": version, "environment": "staging"}), ("/healthz", {"status": "ok"}), ("/readyz", {"status": "ready"})]:
        with urllib.request.urlopen("http://delivery-lab:8080" + path, timeout=5) as response:
            assert response.status == 200
            assert json.load(response) == expected
            if path != "/version":
                expected_cache = "no-store" if cache_policy == "no-store" else None
                assert response.headers.get("Cache-Control") == expected_cache
print("PASS 36 sampled Service requests; version", version, "probe cache policy", cache_policy)
'@
    Invoke-LabKubectl @('exec', $Pod, '--', 'python', '-c', $check, $Version, $CachePolicy) | Write-Host
}
function Assert-HealthyRelease {
    param([string]$Tag, [string]$Version, [string]$CachePolicy)
    Invoke-LabKubectl @('rollout', 'status', 'deployment/delivery-lab', '--timeout=120s') | Write-Host
    $deployment = Invoke-LabKubectl @('get', 'deployment', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
    if ($deployment.status.observedGeneration -ne $deployment.metadata.generation -or
        $deployment.status.updatedReplicas -ne 2 -or $deployment.status.readyReplicas -ne 2 -or
        $deployment.status.availableReplicas -ne 2) { throw 'The release does not have two updated, ready and available replicas.' }
    $pods = Invoke-LabKubectl @('get', 'pods', '-l', 'app.kubernetes.io/instance=delivery-lab', '-o', 'json') | ConvertFrom-Json
    $active = @($pods.items | Where-Object { -not $_.metadata.deletionTimestamp })
    if ($active.Count -ne 2) { throw 'Unexpected active pod count.' }
    foreach ($pod in $active) {
        if ($pod.spec.containers[0].image -ne "platform-delivery-lab:$Tag" -or
            $pod.status.containerStatuses[0].ready -ne $true) { throw 'Unexpected image or readiness.' }
    }
    $slices = Invoke-LabKubectl @('get', 'endpointslices', '-l', 'kubernetes.io/service-name=delivery-lab', '-o', 'json') | ConvertFrom-Json
    $endpoints = @($slices.items.endpoints | Where-Object { $_.conditions.ready -eq $true })
    if ($endpoints.Count -ne 2) { throw 'Expected two ready Service endpoints.' }
    Assert-Service $active[0].metadata.name $Version $CachePolicy
    return ,$active
}

try {
    if (-not (Test-Path -LiteralPath $kubeconfig)) { throw 'Create the dedicated lab cluster first.' }
    New-Item -ItemType Directory -Force (Split-Path $evidencePath -Parent) | Out-Null
    $images = Invoke-Checked docker @('image', 'inspect', 'platform-delivery-lab:release-0.1.0', 'platform-delivery-lab:patch-0.1.1') | ConvertFrom-Json
    if ($images.Count -ne 2 -or $images[0].Id -eq $images[1].Id -or
        $images[0].Config.Labels.'org.opencontainers.image.version' -ne '0.1.0' -or
        $images[1].Config.Labels.'org.opencontainers.image.version' -ne '0.1.1') { throw 'Build both distinct release images first.' }
    $result.images = @($images | ForEach-Object { @{ id = $_.Id; tags = $_.RepoTags; labels = $_.Config.Labels } })
    Invoke-Checked $kind @('load', 'docker-image', 'platform-delivery-lab:release-0.1.0', 'platform-delivery-lab:patch-0.1.1', '--name', 'platform-delivery-lab') | Write-Output
    $existingNamespace = Invoke-LabKubectl @('get', 'namespace', $namespace, '--ignore-not-found', '-o', 'json')
    if ($existingNamespace) {
        $existing = $existingNamespace | ConvertFrom-Json
        if ($existing.metadata.labels.'delivery-lab/exercise' -ne 'release-recovery') { throw 'Refusing to modify an unowned lab-release namespace.' }
    }
    $namespaceFile = Join-Path $root 'work/releases/namespace.yaml'
    @"
apiVersion: v1
kind: Namespace
metadata:
  name: lab-release
  labels:
    delivery-lab/exercise: release-recovery
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
"@ | Set-Content $namespaceFile -Encoding utf8
    Invoke-LabKubectl @('apply', '-f', $namespaceFile) | Write-Output

    Deploy-Version 'release-0.1.0' '0.1.0'
    $baselinePods = Assert-HealthyRelease 'release-0.1.0' '0.1.0' 'absent'
    Record-Phase 'baseline-release' @{ version = '0.1.0'; pods = @($baselinePods.metadata.name) }

    Deploy-Version 'patch-0.1.1' '0.1.1'
    $patchPods = Assert-HealthyRelease 'patch-0.1.1' '0.1.1' 'no-store'
    $status = Invoke-LabHelm @('status', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
    $knownGoodRevision = [int]$status.version
    $result.knownGoodRevision = $knownGoodRevision
    Record-Phase 'patch-release' @{ version = '0.1.1'; revision = $knownGoodRevision; pods = @($patchPods.metadata.name) }

    $rollbackRequired = $true
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $failedUpgrade = Invoke-Native $helm @('--kubeconfig', $kubeconfig, '--kube-context', $context, '-n', $namespace,
        'upgrade', 'delivery-lab', $chart, '--reuse-values', '--set', 'app.ready=false', '--wait', '--timeout', '35s')
    $timer.Stop()
    if ($failedUpgrade.ExitCode -eq 0 -or $failedUpgrade.Output -notmatch 'deadline|timed out|timeout') {
        throw "Expected a rollout timeout, received: $($failedUpgrade.Output)"
    }
    $status = Invoke-LabHelm @('status', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
    if ($status.info.status -ne 'failed') { throw 'Helm did not record the failed release.' }
    $pods = Invoke-LabKubectl @('get', 'pods', '-l', 'app.kubernetes.io/instance=delivery-lab', '-o', 'json') | ConvertFrom-Json
    $active = @($pods.items | Where-Object { -not $_.metadata.deletionTimestamp })
    $bad = @($active | Where-Object { ($_.spec.containers[0].env | Where-Object name -eq APP_READY).value -eq 'false' })
    $good = @($active | Where-Object { $_.status.containerStatuses[0].ready -eq $true })
    if ($bad.Count -ne 1 -or $good.Count -ne 2 -or $bad[0].status.phase -ne 'Running' -or
        $bad[0].status.containerStatuses[0].ready -ne $false -or
        $bad[0].status.containerStatuses[0].restartCount -ne 0) { throw 'Unexpected failed-rollout pod state.' }
    $probeCheck = @'
import json, urllib.request, urllib.error
with urllib.request.urlopen("http://127.0.0.1:8080/healthz", timeout=5) as response:
    assert response.status == 200 and json.load(response) == {"status": "ok"}
try:
    urllib.request.urlopen("http://127.0.0.1:8080/readyz", timeout=5)
except urllib.error.HTTPError as error:
    assert error.code == 503 and json.load(error) == {"status": "not_ready"}
else:
    raise AssertionError("Expected readiness HTTP 503")
print("PASS failed candidate: health 200, readiness 503, process remains alive")
'@
    Invoke-LabKubectl @('exec', $bad[0].metadata.name, '--', 'python', '-c', $probeCheck) | Write-Output
    $slices = Invoke-LabKubectl @('get', 'endpointslices', '-l', 'kubernetes.io/service-name=delivery-lab', '-o', 'json') | ConvertFrom-Json
    $readyTargets = @($slices.items.endpoints | Where-Object { $_.conditions.ready -eq $true } | ForEach-Object { $_.targetRef.name })
    if ($readyTargets.Count -ne 2 -or $bad[0].metadata.name -in $readyTargets -or
        @($readyTargets | Where-Object { $_ -notin @($patchPods.metadata.name) }).Count -ne 0) { throw 'Service endpoint isolation failed.' }
    Assert-Service $good[0].metadata.name '0.1.1' 'no-store'
    $result.expectedFailure = @{ exitCode = $failedUpgrade.ExitCode; output = $failedUpgrade.Output; elapsedSeconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2); revision = $status.version; candidate = $bad[0].metadata.name; candidateRestarts = 0; readyServiceTargets = $readyTargets }
    Invoke-LabKubectl @('get', 'events', '--sort-by=.metadata.creationTimestamp') | Set-Content (Join-Path $root 'work/releases/failure-events.txt') -Encoding utf8
    Invoke-LabKubectl @('describe', 'deployment', 'delivery-lab') | Set-Content (Join-Path $root 'work/releases/failed-deployment.txt') -Encoding utf8
    Record-Phase 'expected-readiness-failure' $result.expectedFailure

    Invoke-LabHelm @('rollback', 'delivery-lab', "$knownGoodRevision", '--wait', '--timeout', '120s') | Write-Output
    $recoveredPods = Assert-HealthyRelease 'patch-0.1.1' '0.1.1' 'no-store'
    $status = Invoke-LabHelm @('status', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
    $values = Invoke-LabHelm @('get', 'values', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
    if ($status.info.status -ne 'deployed' -or [int]$status.version -le [int]$result.expectedFailure.revision -or
        $values.app.ready -ne $true) { throw 'Rollback did not restore the Helm release state.' }
    $rollbackRequired = $false
    $result.recoveredRevision = [int]$status.version
    Record-Phase 'verified-rollback' @{ revision = $status.version; restoredFromRevision = $knownGoodRevision; version = '0.1.1'; pods = @($recoveredPods.metadata.name) }
    $result.history = Invoke-LabHelm @('history', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
    $result.success = $true
}
catch {
    $primaryFailure = $_
    $result.error = $_.ToString()
    & $kubectl --kubeconfig $kubeconfig --context $context -n $namespace get pods -o wide
    & $kubectl --kubeconfig $kubeconfig --context $context -n $namespace get events --sort-by=.metadata.creationTimestamp
    if ($rollbackRequired -and $knownGoodRevision) {
        try {
            Invoke-LabHelm @('rollback', 'delivery-lab', "$knownGoodRevision", '--wait', '--timeout', '120s') | Write-Output
            $null = Assert-HealthyRelease 'patch-0.1.1' '0.1.1' 'no-store'
            $result.emergencyRecovery = 'Verified; the exercise still fails because an assertion failed.'
        }
        catch {
            $result.recoveryError = $_.ToString()
            throw "Exercise failed: $primaryFailure`nRecovery also failed: $_"
        }
    }
    throw $primaryFailure
}
finally {
    $result.finishedUtc = [DateTime]::UtcNow.ToString('o')
    New-Item -ItemType Directory -Force (Split-Path $evidencePath -Parent) | Out-Null
    $result | ConvertTo-Json -Depth 15 | Set-Content $evidencePath -Encoding utf8
}
Write-Output ($result | ConvertTo-Json -Depth 15 -Compress)
Write-Output 'Release, patch, expected failure, and verified Helm rollback passed. lab-release remains available for inspection.'
exit 0
