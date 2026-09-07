#Requires -Version 5.1
<#
.SYNOPSIS
  Trusts the FuelPoint developer certificate so Windows will install the .msix.

.DESCRIPTION
  Imports certs/FuelPointDevCert.cer (or a copy next to this script) into
  LocalMachine\TrustedPeople. Optionally also imports into LocalMachine\Root.
  Enables sideloading of trusted apps. Must run as Administrator.

.EXAMPLE
  Right-click PowerShell > Run as administrator, then:
    powershell -ExecutionPolicy Bypass -File .\install_client_cert.ps1

.EXAMPLE
  .\install_client_cert.ps1 -IncludeRoot
#>
[CmdletBinding()]
param(
  [string]$CertificatePath,
  [switch]$IncludeRoot,
  [switch]$NoElevate,
  [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]$identity
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step {
  param([string]$Message)
  Write-Host "[FuelPoint] $Message" -ForegroundColor Cyan
}

function Resolve-CertificatePath {
  param([string]$Requested)

  if ($Requested) {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Requested)
    if (Test-Path -LiteralPath $resolved) { return $resolved }
    throw "Certificate not found: $resolved"
  }

  $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $candidates = @(
    (Join-Path $scriptDir 'FuelPointDevCert.cer'),
    (Join-Path $scriptDir '..\certs\FuelPointDevCert.cer'),
    (Join-Path (Get-Location) 'FuelPointDevCert.cer'),
    (Join-Path (Get-Location) 'certs\FuelPointDevCert.cer')
  )

  foreach ($candidate in $candidates) {
    $full = [System.IO.Path]::GetFullPath($candidate)
    if (Test-Path -LiteralPath $full) { return $full }
  }

  throw @'
Could not find FuelPointDevCert.cer.
Place it next to this script, or in a certs folder, then run again.
'@
}

if (-not (Test-Administrator)) {
  if ($NoElevate) {
    throw 'This script must run as Administrator. Right-click PowerShell and choose Run as administrator.'
  }

  Write-Step 'Requesting Administrator approval (Windows will show a UAC prompt)...'
  $relaunch = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $PSCommandPath
  )
  if ($CertificatePath) { $relaunch += @('-CertificatePath', $CertificatePath) }
  if ($IncludeRoot) { $relaunch += '-IncludeRoot' }
  if ($NoPause) { $relaunch += '-NoPause' }

  $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch -PassThru -Wait
  exit $process.ExitCode
}

$cerPath = Resolve-CertificatePath -Requested $CertificatePath
Write-Step "Installing certificate: $cerPath"

$trustedPeople = Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'
Write-Host "  Trusted People : $($trustedPeople.Thumbprint)" -ForegroundColor Green

if ($IncludeRoot) {
  $root = Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\Root'
  Write-Host "  LocalMachine Root : $($root.Thumbprint)" -ForegroundColor Green
}

$unlockKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
if (-not (Test-Path -LiteralPath $unlockKey)) {
  New-Item -Path $unlockKey -Force | Out-Null
}
New-ItemProperty -Path $unlockKey -Name 'AllowAllTrustedApps' -Value 1 -PropertyType DWord -Force | Out-Null
Write-Step 'Enabled Windows sideloading of trusted apps (AllowAllTrustedApps).'

Write-Host ''
Write-Host 'Certificate installed. Windows will now trust FuelPoint Station OS.msix.' -ForegroundColor Green
Write-Host 'Next: double-click "FuelPoint Station OS.msix" to install or update the software.'
Write-Host ''

if (-not $NoPause) {
  Write-Host 'Press Enter to close...'
  try {
    [void][Console]::ReadLine()
  } catch {
    Start-Sleep -Seconds 3
  }
}
