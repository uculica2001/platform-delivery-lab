#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$extension = if ($IsWindows) { '.exe' } else { '' }
$kind = Join-Path $root "work/tools/kind$extension"
if (-not (Test-Path -LiteralPath $kind)) { throw 'Run scripts/install-local-tools.ps1 first.' }
$clusters = & $kind get clusters
if ($LASTEXITCODE -ne 0) { throw 'Could not list kind clusters.' }
if ($clusters -contains 'platform-delivery-lab') {
    throw 'The lab cluster already exists. Reuse work/kubeconfig; this script will not replace it.'
}
& $kind create cluster --name platform-delivery-lab --config (Join-Path $root 'kind/cluster.yaml') --kubeconfig (Join-Path $root 'work/kubeconfig') --wait 180s
if ($LASTEXITCODE -ne 0) { throw 'Cluster creation failed. Inspect kind diagnostics before retrying.' }
Write-Output 'Lab cluster created. Its kubeconfig is work/kubeconfig; your default kubeconfig was not changed.'
