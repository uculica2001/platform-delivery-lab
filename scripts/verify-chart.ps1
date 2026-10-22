#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$extension = if ($IsWindows) { '.exe' } else { '' }
$helm = Join-Path $root "work/tools/helm$extension"
$chart = Join-Path $root 'charts/delivery-lab'
if (-not (Test-Path -LiteralPath $helm)) { throw 'Run scripts/install-local-tools.ps1 first.' }
foreach ($environment in @('dev', 'staging')) {
    & $helm lint $chart --strict -f (Join-Path $chart "values-$environment.yaml")
    if ($LASTEXITCODE -ne 0) { throw "Chart lint failed for $environment." }
    $rendered = & $helm template delivery-lab $chart --namespace "lab-$environment" -f (Join-Path $chart "values-$environment.yaml")
    if ($LASTEXITCODE -ne 0) { throw "Chart rendering failed for $environment." }
    $rendered | Set-Content (Join-Path $root "work/rendered-$environment.yaml") -Encoding utf8
}
foreach ($invalidSetting in @('replicaCount=0', 'app.ready=not-a-boolean', 'image.tag=')) {
    $output = & $helm template delivery-lab $chart --set $invalidSetting 2>&1
    if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'schema') {
        throw "Expected schema rejection for $invalidSetting; received: $output"
    }
    Write-Output "PASS schema rejected $invalidSetting"
}
Write-Output 'Chart lint, rendering, and three invalid-value checks passed.'
# GitHub's pwsh wrapper propagates LASTEXITCODE; the last Helm failure above is expected.
exit 0
# GitHub's pwsh wrapper propagates LASTEXITCODE; the last Helm failure above is expected.
exit 0
