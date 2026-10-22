#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$baselineCommit = 'bd9cec24bfc7272714f187da4864adc748327780'
$releaseWork = Join-Path $root 'work/releases'
$baselineSource = Join-Path $releaseWork 'baseline-source'
New-Item -ItemType Directory -Force $baselineSource | Out-Null

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE." }
}

# The old image must come from old source, not just a second tag on the patch image.
$archive = Join-Path $releaseWork 'baseline.tar'
Invoke-Checked git @('-C', $root, 'archive', '--format=tar', "--output=$archive", $baselineCommit)
Invoke-Checked tar @('-xf', $archive, '-C', $baselineSource)
# Align line endings when declarations match so COPY can share the dependency layer.
$baselineRequirements = Join-Path $baselineSource 'requirements.txt'
$requirementsText = [IO.File]::ReadAllText($baselineRequirements).Replace("`r`n", "`n")
$currentRequirements = Join-Path $root 'requirements.txt'
if ($requirementsText -eq [IO.File]::ReadAllText($currentRequirements).Replace("`r`n", "`n")) {
    [IO.File]::WriteAllBytes($baselineRequirements, [IO.File]::ReadAllBytes($currentRequirements))
}
$revision = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the patch source revision.' }
$dirty = & git -C $root status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the patch source state.' }
if ($dirty) { $revision = "$revision-dirty" }
Invoke-Checked docker @('build', '--target', 'runtime', '--label', 'org.opencontainers.image.version=0.1.0',
    '--label', "org.opencontainers.image.revision=$baselineCommit", '-t', 'platform-delivery-lab:release-0.1.0', $baselineSource)
Invoke-Checked docker @('build', '--target', 'runtime', '--label', 'org.opencontainers.image.version=0.1.1',
    '--label', "org.opencontainers.image.revision=$revision", '-t', 'platform-delivery-lab:patch-0.1.1', $root)
$baselinePackages = & docker run --rm --network none platform-delivery-lab:release-0.1.0 python -m pip freeze
if ($LASTEXITCODE -ne 0) { throw 'Baseline dependency inspection failed.' }
$patchPackages = & docker run --rm --network none platform-delivery-lab:patch-0.1.1 python -m pip freeze
if ($LASTEXITCODE -ne 0) { throw 'Patch dependency inspection failed.' }
if (($baselinePackages -join "`n") -ne ($patchPackages -join "`n")) {
    throw 'Baseline and patch Python dependencies differ. Resolve dependency drift before comparing the patch.'
}
$patchPackages | Set-Content (Join-Path $releaseWork 'python-packages.txt') -Encoding utf8
$images = & docker image inspect platform-delivery-lab:release-0.1.0 platform-delivery-lab:patch-0.1.1
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect release images.' }
$images | Set-Content (Join-Path $releaseWork 'images.json') -Encoding utf8
Write-Output 'Built release-0.1.0 from frozen source and patch-0.1.1 from the current checkout; image metadata saved in work/releases/images.json.'
