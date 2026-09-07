#Requires -Version 5.1
<#
.SYNOPSIS
  Creates a self-signed FuelPoint code-signing certificate for MSIX sideloading.

.DESCRIPTION
  Generates CN=FuelPoint, O=RetroSoft, C=PK with Code Signing EKU (1.3.6.1.5.5.7.3.3).
  Exports:
    certs/FuelPointDevCert.cer  — public cert for client machines
    certs/FuelPointDevCert.pfx  — private key used by msix:create (not for clients)

  Run once on the development PC before scripts/build_msix.ps1.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\generate_cert.ps1
#>
[CmdletBinding()]
param(
  [string]$Password = 'FuelPointDev',
  [int]$ValidYears = 5,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CertsDir = Join-Path $RepoRoot 'certs'
$CerPath = Join-Path $CertsDir 'FuelPointDevCert.cer'
$PfxPath = Join-Path $CertsDir 'FuelPointDevCert.pfx'
$Subject = 'CN=FuelPoint, O=RetroSoft, C=PK'
$FriendlyName = 'FuelPoint Station OS Developer'
$StorePath = 'Cert:\CurrentUser\My'
# Enhanced Key Usage: Code Signing
$CodeSigningEkuOid = '1.3.6.1.5.5.7.3.3'

function Write-Step {
  param([string]$Message)
  Write-Host "[FuelPoint] $Message" -ForegroundColor Cyan
}

if (-not (Test-Path -LiteralPath $CertsDir)) {
  New-Item -ItemType Directory -Path $CertsDir | Out-Null
}

if ((Test-Path -LiteralPath $CerPath) -or (Test-Path -LiteralPath $PfxPath)) {
  if (-not $Force) {
    Write-Host "[FuelPoint] Certificate files already exist:" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $CerPath) { Write-Host "  $CerPath" }
    if (Test-Path -LiteralPath $PfxPath) { Write-Host "  $PfxPath" }
    Write-Host "Re-run with -Force to replace them."
    exit 0
  }
  Write-Step 'Removing existing certificate files (-Force).'
  Remove-Item -LiteralPath $CerPath, $PfxPath -ErrorAction SilentlyContinue
}

Write-Step "Removing previous CurrentUser\\My certificates named '$FriendlyName'."
Get-ChildItem -Path $StorePath |
  Where-Object {
    $_.FriendlyName -eq $FriendlyName -or
    ($_.Subject -like '*CN=FuelPoint*' -and $_.Subject -like '*O=RetroSoft*')
  } |
  ForEach-Object {
    Remove-Item -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
  }

Write-Step "Creating self-signed code-signing certificate ($ValidYears year(s))."
$notAfter = (Get-Date).AddYears($ValidYears)
$cert = New-SelfSignedCertificate `
  -Type Custom `
  -Subject $Subject `
  -FriendlyName $FriendlyName `
  -KeyUsage DigitalSignature `
  -KeyAlgorithm RSA `
  -KeyLength 2048 `
  -HashAlgorithm SHA256 `
  -KeyExportPolicy Exportable `
  -CertStoreLocation $StorePath `
  -NotAfter $notAfter `
  -TextExtension @(
    "2.5.29.37={text}$CodeSigningEkuOid",
    '2.5.29.19={text}'
  )

if ($null -eq $cert) {
  throw 'New-SelfSignedCertificate did not return a certificate.'
}

Write-Step "Exporting public certificate: $CerPath"
Export-Certificate -Cert $cert -FilePath $CerPath -Type CERT | Out-Null

Write-Step "Exporting signing PFX: $PfxPath"
$securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $securePassword | Out-Null

$pubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
if (Test-Path -LiteralPath $pubspecPath) {
  $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
  $escapedSubject = $cert.Subject.Replace('\', '\\').Replace('"', '\"')
  $updated = [regex]::Replace(
    $pubspec,
    '(?m)^(\s*publisher:\s*).*$',
    ('$1"' + $escapedSubject + '"'),
    1
  )
  if ($updated -ne $pubspec) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText(
      $pubspecPath,
      ($updated.TrimEnd() + [Environment]::NewLine),
      $utf8NoBom
    )
    Write-Step "Updated pubspec.yaml publisher to match the certificate Subject."
  }
}

Write-Host ''
Write-Host 'Certificate created.' -ForegroundColor Green
Write-Host "  Subject     : $($cert.Subject)"
Write-Host "  Thumbprint  : $($cert.Thumbprint)"
Write-Host "  Valid until : $($cert.NotAfter.ToString('yyyy-MM-dd'))"
Write-Host "  EKU         : Code Signing ($CodeSigningEkuOid)"
Write-Host "  Public CER  : $CerPath"
Write-Host "  Signing PFX : $PfxPath"
Write-Host "  PFX password: $Password"
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Keep FuelPointDevCert.pfx on this build PC only. Do not send it to clients.'
Write-Host '  2. Run scripts\build_msix.ps1 to produce the signed installer.'
Write-Host '  3. Give clients FuelPointDevCert.cer plus scripts\install_client_cert.ps1.'
Write-Host ''
Write-Host 'To test-install the MSIX on this PC, run scripts\install_client_cert.ps1 as Administrator.'
