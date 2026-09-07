#Requires -Version 5.1
<#
.SYNOPSIS
  Builds the Windows release binary and a signed FuelPoint Station OS MSIX.

.DESCRIPTION
  1. flutter clean
  2. flutter pub get
  3. flutter build windows --release
  4. flutter pub run msix:create  (signs with certs/FuelPointDevCert.pfx)

  Output:
    build\windows\x64\runner\Release\FuelPoint Station OS.msix
    dist\  (client-ready copy of the installer, public cert, and install script)

  Prerequisites:
    Run scripts\generate_cert.ps1 once on this PC.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\build_msix.ps1
#>
[CmdletBinding()]
param(
  [string]$CertificatePassword = 'FuelPointDev',
  [switch]$SkipClean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PfxPath = Join-Path $RepoRoot 'certs\FuelPointDevCert.pfx'
$CerPath = Join-Path $RepoRoot 'certs\FuelPointDevCert.cer'
$ReleaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
$DistDir = Join-Path $RepoRoot 'dist'
$MsixName = 'FuelPoint Station OS.msix'

function Write-Step {
  param([string]$Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Flutter {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  Write-Step $Label
  Push-Location $RepoRoot
  try {
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Label failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
}

Set-Location $RepoRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'flutter is not on PATH. Open a Flutter-enabled terminal and try again.'
}

if (-not (Test-Path -LiteralPath $PfxPath)) {
  throw @"
Signing certificate not found: $PfxPath

Generate it first:
  powershell -ExecutionPolicy Bypass -File .\scripts\generate_cert.ps1
"@
}

Write-Host 'FuelPoint Station OS — MSIX release build' -ForegroundColor Green
Write-Host "Repository : $RepoRoot"
Write-Host "Certificate: $PfxPath"

if (-not $SkipClean) {
  Invoke-Flutter -Arguments @('clean') -Label 'flutter clean'
} else {
  Write-Host 'Skipping flutter clean (-SkipClean).' -ForegroundColor Yellow
}

Invoke-Flutter -Arguments @('pub', 'get') -Label 'flutter pub get'
Invoke-Flutter -Arguments @('build', 'windows', '--release') -Label 'flutter build windows --release'

$securePassword = ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText
$pfxData = Get-PfxData -FilePath $PfxPath -Password $securePassword
$publisher = $pfxData.EndEntityCertificates[0].Subject
Write-Host "Publisher   : $publisher"

Write-Step 'flutter pub run msix:create (sign MSIX)'
Push-Location $RepoRoot
try {
  & flutter pub run msix:create `
    --build-windows false `
    --certificate-path $PfxPath `
    --certificate-password $CertificatePassword `
    --publisher $publisher `
    --output-path $ReleaseDir `
    --output-name 'FuelPoint Station OS'
  if ($LASTEXITCODE -ne 0) {
    throw "msix:create failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

$msixPath = Join-Path $ReleaseDir $MsixName
if (-not (Test-Path -LiteralPath $msixPath)) {
  $found = Get-ChildItem -Path $ReleaseDir -Filter '*.msix' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $found) {
    throw "MSIX was not created in $ReleaseDir"
  }
  $msixPath = $found.FullName
}

if (-not (Test-Path -LiteralPath $DistDir)) {
  New-Item -ItemType Directory -Path $DistDir | Out-Null
}

Copy-Item -LiteralPath $msixPath -Destination (Join-Path $DistDir $MsixName) -Force
if (Test-Path -LiteralPath $CerPath) {
  Copy-Item -LiteralPath $CerPath -Destination (Join-Path $DistDir 'FuelPointDevCert.cer') -Force
  Copy-Item -LiteralPath $CerPath -Destination (Join-Path $ReleaseDir 'FuelPointDevCert.cer') -Force
}
Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\install_client_cert.ps1') -Destination (Join-Path $DistDir 'install_client_cert.ps1') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\install_fuelpoint_bundle.ps1') -Destination (Join-Path $DistDir 'install_fuelpoint_bundle.ps1') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\Install.cmd') -Destination (Join-Path $DistDir 'Install.cmd') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'DISTRIBUTION_README.txt') -Destination (Join-Path $DistDir 'DISTRIBUTION_README.txt') -Force

Write-Host ''
Write-Host 'Build complete.' -ForegroundColor Green
Write-Host "  Installer : $msixPath"
Write-Host "  Client kit: $DistDir"
Write-Host ''
Write-Host 'Give the client the folder dist\. They double-click Install.cmd.'
