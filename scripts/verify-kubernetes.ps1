#requires -Version 7.0
param(
    [string]$ImageTag = '0.1.0',
    [string]$AppVersion = '0.1.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$extension = if ($IsWindows) { '.exe' } else { '' }
$helm = Join-Path $root "work/tools/helm$extension"
$kubectl = Join-Path $root "work/tools/kubectl$extension"
$kubeconfig = Join-Path $root 'work/kubeconfig'
$context = 'kind-platform-delivery-lab'
$chart = Join-Path $root 'charts/delivery-lab'
if (-not (Test-Path -LiteralPath $kubeconfig)) { throw 'Run scripts/create-local-cluster.ps1 first.' }

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE): $($output -join "`n")" }
    return ($output -join "`n")
}
function Invoke-Kubectl {
    param([string[]]$Arguments)
    Invoke-Checked $kubectl (@('--kubeconfig', $kubeconfig, '--context', $context) + $Arguments)
}
function Invoke-Helm {
    param([string[]]$Arguments)
    Invoke-Checked $helm (@('--kubeconfig', $kubeconfig, '--kube-context', $context) + $Arguments)
}

foreach ($environment in @('dev', 'staging')) {
    $namespace = "lab-$environment"
    try {
        # Namespace ownership belongs to the lab setup, not to the Helm release.
        $namespaceFile = Join-Path $root "work/namespace-$environment.yaml"
        @"
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
"@ | Set-Content $namespaceFile -Encoding utf8
        Invoke-Kubectl @('apply', '-f', $namespaceFile) | Write-Output
        Invoke-Helm @('upgrade', '--install', 'delivery-lab', $chart, '--namespace', $namespace,
            '-f', (Join-Path $chart "values-$environment.yaml"),
            '--set-string', "image.tag=$ImageTag", '--set-string', "app.version=$AppVersion",
            '--set', 'image.pullPolicy=Never', '--wait', '--timeout', '180s') | Write-Output
        Invoke-Kubectl @('-n', $namespace, 'rollout', 'status', 'deployment/delivery-lab', '--timeout=120s') | Write-Output
        $deployment = Invoke-Kubectl @('-n', $namespace, 'get', 'deployment', 'delivery-lab', '-o', 'json') | ConvertFrom-Json
        $expectedReplicas = if ($environment -eq 'dev') { 1 } else { 2 }
        if ($deployment.status.observedGeneration -ne $deployment.metadata.generation -or
            $deployment.spec.replicas -ne $expectedReplicas -or
            $deployment.status.updatedReplicas -ne $expectedReplicas -or
            $deployment.status.readyReplicas -ne $expectedReplicas -or
            $deployment.status.availableReplicas -ne $expectedReplicas) {
            throw "Unexpected deployment state in $namespace."
        }
        $pods = Invoke-Kubectl @('-n', $namespace, 'get', 'pods', '-l', 'app.kubernetes.io/instance=delivery-lab', '-o', 'json') | ConvertFrom-Json
        $runningPods = @($pods.items | Where-Object { -not $_.metadata.deletionTimestamp })
        if ($runningPods.Count -ne $expectedReplicas) { throw "Unexpected pod count in $namespace." }
        foreach ($pod in $runningPods) {
            $container = $pod.spec.containers[0]
            if ($pod.spec.securityContext.runAsUser -ne 10001 -or
                $pod.spec.securityContext.runAsGroup -ne 10001 -or
                $pod.spec.securityContext.runAsNonRoot -ne $true -or
                $pod.spec.securityContext.seccompProfile.type -ne 'RuntimeDefault' -or
                $container.securityContext.readOnlyRootFilesystem -ne $true -or
                $container.securityContext.allowPrivilegeEscalation -ne $false -or
                'ALL' -notin $container.securityContext.capabilities.drop -or
                $pod.spec.automountServiceAccountToken -ne $false) {
                throw "Unexpected security configuration on $($pod.metadata.name)."
            }
            $logs = Invoke-Kubectl @('-n', $namespace, 'logs', $pod.metadata.name, '--all-containers=true')
            if ($logs -match '\[(ERROR|CRITICAL)\]|Traceback \(most recent call last\)') {
                throw "Runtime errors on $($pod.metadata.name): $logs"
            }
        }
        # Use the application's own standard library to exercise DNS + ClusterIP routing.
        $requestCheck = @'
import json, os, sys, urllib.request
environment, version = sys.argv[1:]
expected = {"/": {"service": "platform-delivery-lab"}, "/healthz": {"status": "ok"}, "/readyz": {"status": "ready"}, "/version": {"environment": environment, "version": version}}
for path, body in expected.items():
    with urllib.request.urlopen("http://delivery-lab:8080" + path, timeout=5) as response:
        assert response.status == 200, (path, response.status)
        actual = json.load(response)
        assert actual == body, (path, actual, body)
    print("PASS Service request", path, body)
assert (os.getuid(), os.getgid()) == (10001, 10001)
with open("/tmp/delivery-lab-check", "w") as output:
    output.write("temporary storage works")
os.remove("/tmp/delivery-lab-check")
try:
    with open("/service/should-not-be-writable", "w"):
        pass
except OSError as error:
    assert error.errno == 30, error
else:
    raise AssertionError("Root filesystem was writable")
assert not os.path.exists("/var/run/secrets/kubernetes.io/serviceaccount/token")
print("PASS runtime UID/GID, read-only root, writable /tmp, and absent API token")
'@
        Invoke-Kubectl @('-n', $namespace, 'exec', $runningPods[0].metadata.name, '--', 'python', '-c', $requestCheck, $environment, $AppVersion) | Write-Output
        $slices = Invoke-Kubectl @('-n', $namespace, 'get', 'endpointslices', '-l', 'kubernetes.io/service-name=delivery-lab', '-o', 'json') | ConvertFrom-Json
        $readyEndpoints = @($slices.items.endpoints | Where-Object { $_.conditions.ready -eq $true })
        if ($readyEndpoints.Count -ne $expectedReplicas) { throw "Unexpected ready Service endpoints in $namespace." }
        Write-Output "PASS ${namespace}: $expectedReplicas ready replicas and Service endpoints"
    }
    catch {
        $failure = $_
        & $kubectl --kubeconfig $kubeconfig --context $context -n $namespace get pods -o wide
        & $kubectl --kubeconfig $kubeconfig --context $context -n $namespace describe deployment delivery-lab
        & $kubectl --kubeconfig $kubeconfig --context $context -n $namespace get events --sort-by=.metadata.creationTimestamp
        & $kubectl --kubeconfig $kubeconfig --context $context -n $namespace logs -l app.kubernetes.io/instance=delivery-lab --all-containers=true --tail=100
        throw $failure
    }
}
Write-Output 'Kubernetes verification passed for dev and staging. Releases remain installed for inspection.'
