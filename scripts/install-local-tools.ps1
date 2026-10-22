#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root 'work/tools'
$lock = Get-Content (Join-Path $PSScriptRoot 'local-tools.json') -Raw | ConvertFrom-Json
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
    throw 'This bootstrap currently supports Windows/Linux x64 only.'
}
if ($IsWindows) { $platform = 'windows'; $extension = '.exe'; $archiveExtension = 'zip' }
elseif ($IsLinux) { $platform = 'linux'; $extension = ''; $archiveExtension = 'tar.gz' }
else { throw 'This bootstrap currently supports Windows/Linux only.' }
New-Item -ItemType Directory -Force $tools | Out-Null

function Get-VerifiedDownload {
    param([string]$Url, [string]$Destination, [string]$Sha256)
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -Uri $Url -OutFile $Destination
    }
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Checksum mismatch: $Destination. Remove that file and retry after checking the source."
    }
}

$kindAsset = "kind-$platform-amd64"
$kindDownload = Join-Path $tools $kindAsset
Get-VerifiedDownload "https://github.com/kubernetes-sigs/kind/releases/download/$($lock.kindVersion)/$kindAsset" $kindDownload $lock.$platform.kindSha256
Copy-Item -LiteralPath $kindDownload -Destination (Join-Path $tools "kind$extension") -Force
$helmAsset = "helm-$($lock.helmVersion)-$platform-amd64.$archiveExtension"
$helmDownload = Join-Path $tools $helmAsset
Get-VerifiedDownload "https://get.helm.sh/$helmAsset" $helmDownload $lock.$platform.helmSha256
if ($IsWindows) { Expand-Archive -LiteralPath $helmDownload -DestinationPath $tools -Force }
else {
    & tar -xzf $helmDownload -C $tools
    if ($LASTEXITCODE -ne 0) { throw 'Helm extraction failed.' }
}
Copy-Item -LiteralPath (Join-Path $tools "$platform-amd64/helm$extension") -Destination (Join-Path $tools "helm$extension") -Force
$kubectlDownload = Join-Path $tools "kubectl$extension"
Get-VerifiedDownload "https://dl.k8s.io/release/$($lock.kubectlVersion)/bin/$platform/amd64/kubectl$extension" $kubectlDownload $lock.$platform.kubectlSha256
if ($IsLinux) {
    & chmod +x (Join-Path $tools 'kind') (Join-Path $tools 'helm') $kubectlDownload
    if ($LASTEXITCODE -ne 0) { throw 'Setting executable permissions failed.' }
}
& (Join-Path $tools "kind$extension") version
if ($LASTEXITCODE -ne 0) { throw 'kind version check failed.' }
& (Join-Path $tools "helm$extension") version --short
if ($LASTEXITCODE -ne 0) { throw 'Helm version check failed.' }
& $kubectlDownload version --client
if ($LASTEXITCODE -ne 0) { throw 'kubectl version check failed.' }
Write-Output 'Verified tools installed under work/tools; system PATH was not changed.'
