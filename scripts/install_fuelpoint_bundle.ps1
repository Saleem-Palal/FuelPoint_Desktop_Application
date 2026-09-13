#Requires -Version 5.1
<#
.SYNOPSIS
  Installs the FuelPoint certificate and the MSIX in one step.

.DESCRIPTION
  Used by install.bat (double-click). Imports FuelPointDevCert.cer into
  LocalMachine\TrustedPeople and LocalMachine\Root, enables sideloading,
  then installs or updates FuelPoint Station OS.msix.

  Must run as Administrator. install.bat requests elevation automatically.
#>
[CmdletBinding()]
param(
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
  Write-Host ''
  Write-Host "[FuelPoint] $Message" -ForegroundColor Cyan
}

function Get-SearchRoots {
  $roots = New-Object System.Collections.Generic.List[string]
  $scriptDir = $PSScriptRoot
  if ($scriptDir) { [void]$roots.Add($scriptDir) }
  [void]$roots.Add((Get-Location).Path)
  if ($scriptDir) {
    $parent = Split-Path -Parent $scriptDir
    if ($parent) {
      [void]$roots.Add((Join-Path $parent 'dist'))
      [void]$roots.Add((Join-Path $parent 'certs'))
      [void]$roots.Add((Join-Path $parent 'build\windows\x64\runner\Release'))
    }
  }
  return @($roots | Select-Object -Unique)
}

function Find-Payload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FileName
  )

  foreach ($root in Get-SearchRoots) {
    if (-not $root) { continue }
    $candidate = Join-Path $root $FileName
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "Could not find $FileName. Keep install.bat, the .cer, and the .msix in the same folder."
}

function Install-SideloadPolicy {
  $unlockKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
  if (-not (Test-Path -LiteralPath $unlockKey)) {
    New-Item -Path $unlockKey -Force | Out-Null
  }
  New-ItemProperty -Path $unlockKey -Name 'AllowAllTrustedApps' -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $unlockKey -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -PropertyType DWord -Force | Out-Null

  $policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx'
  if (-not (Test-Path -LiteralPath $policyKey)) {
    New-Item -Path $policyKey -Force | Out-Null
  }
  New-ItemProperty -Path $policyKey -Name 'AllowAllTrustedApps' -Value 1 -PropertyType DWord -Force | Out-Null
}

function Install-MsixPackage {
  param([string]$MsixPath)

  $addParams = @{
    Path                       = $MsixPath
    ForceApplicationShutdown   = $true
    ErrorAction                = 'Stop'
  }
  $command = Get-Command Add-AppxPackage -ErrorAction Stop
  if ($command.Parameters.ContainsKey('ForceUpdateFromAnyVersion')) {
    Add-AppxPackage @addParams -ForceUpdateFromAnyVersion
  } else {
    Add-AppxPackage @addParams
  }
}

function Start-FuelPointApp {
  $pkg = Get-AppxPackage | Where-Object { $_.Name -like 'com.fuelpoint.stationos*' } | Select-Object -First 1
  if ($null -eq $pkg) { return }
  try {
    $manifest = Get-AppxPackageManifest -Package $pkg
    $appId = $manifest.Package.Applications.Application.Id
    if ($appId -is [System.Array]) { $appId = $appId[0] }
    Start-Process ("shell:AppsFolder\{0}!{1}" -f $pkg.PackageFamilyName, $appId) | Out-Null
  } catch {
    # Start menu shortcut is enough if auto-launch fails.
  }
}

$exitCode = 0
try {
  Write-Host 'FuelPoint Station OS  |  RetroSoft setup' -ForegroundColor Green
  Write-Host 'This will trust the RetroSoft certificate and install the application.'

  if (-not (Test-Administrator)) {
    throw 'This installer must run as Administrator. Close this window and double-click install.bat, then click Yes.'
  }

  $cerPath = Find-Payload -FileName 'FuelPointDevCert.cer'
  $msixPath = Find-Payload -FileName 'FuelPoint Station OS.msix'

  Get-Item -LiteralPath $cerPath, $msixPath | Unblock-File -ErrorAction SilentlyContinue

  Write-Step "Installing certificate: $cerPath"
  $trusted = Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'
  Write-Host "  Trusted People : $($trusted.Thumbprint)" -ForegroundColor Green
  $root = Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\Root'
  Write-Host "  Trusted Root   : $($root.Thumbprint)" -ForegroundColor Green

  Write-Step 'Allowing trusted app sideloading on this PC'
  Install-SideloadPolicy
  Write-Host '  Sideloading enabled.' -ForegroundColor Green

  Write-Step "Installing application: $msixPath"
  Install-MsixPackage -MsixPath $msixPath
  Write-Host '  FuelPoint Station OS is installed.' -ForegroundColor Green

  Write-Step 'Launching FuelPoint Station OS'
  Start-FuelPointApp

  Write-Host ''
  Write-Host 'Setup complete. You can also open FuelPoint Station OS from the Start menu.' -ForegroundColor Green
} catch {
  $exitCode = 1
  Write-Host ''
  Write-Host 'Setup failed.' -ForegroundColor Red
  Write-Host $_.Exception.Message
  Write-Host ''
  Write-Host 'If Windows blocked the app, turn on Developer Mode or Sideload apps in Windows Settings, then double-click install.bat again.'
}

if (-not $NoPause) {
  Write-Host ''
  Write-Host 'Press Enter to close...'
  try {
    [void][Console]::ReadLine()
  } catch {
    Start-Sleep -Seconds 4
  }
}

exit $exitCode
