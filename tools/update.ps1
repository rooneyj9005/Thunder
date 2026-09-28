#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "",
    [string]$PackwizSide = "",
    [string]$PackwizExtraFlags = "",
    [switch]$CleanInstall,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

# functions.ps1 sits one level up, at the server root.
$functionsScript = @(
    (Join-Path $PSScriptRoot "functions.ps1"),
    (Join-Path (Split-Path -Parent $PSScriptRoot) "functions.ps1")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $functionsScript) {
    throw "functions.ps1 not found next to or above this script."
}
. $functionsScript

# The server directory is the folder above tools/. This script defaulted to its
# own folder, which was right when it lived at the root and wrong once it moved:
# run by hand, it synced a whole second copy of the pack into tools/ and left the
# server itself as it was.
$defaultDir = if ($Dir) {
    $Dir
}
elseif ($PSScriptRoot) {
    Split-Path -Parent $PSScriptRoot
}
elseif ($PSCommandPath) {
    Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}
else {
    (Get-Location).Path
}

Set-Location $defaultDir

Confirm-SupportedJava

$resolvedPackwizUrl = Resolve-StringSetting $PackwizUrl $env:PACKWIZ_URL "https://packwiz.thunder.john.rooney.scot/pack.toml"
$resolvedPackwizSide = Resolve-StringSetting $PackwizSide $env:PACKWIZ_SIDE ""
$resolvedPackwizExtraFlags = Resolve-StringSetting $PackwizExtraFlags $env:PACKWIZ_EXTRA_FLAGS ""
$resolvedCleanInstall = $CleanInstall -or ($env:CLEAN_INSTALL -match '^(1|true|yes)$')

if (-not $resolvedPackwizSide) {
    throw "PACKWIZ_SIDE must be set to 'server' or 'both'. This script syncs a Thunder server. Running it inside a client instance replaces your client mods with the server set."
}

if ($resolvedPackwizSide -notin @("server", "both")) {
    throw "PACKWIZ_SIDE must be 'server' or 'both'."
}

Assert-PackwizUrl "PACKWIZ_URL" $resolvedPackwizUrl

Assert-ExtraFlags "PACKWIZ_EXTRA_FLAGS" $resolvedPackwizExtraFlags

if ($resolvedCleanInstall) {
    Write-Host "Clean install - wiping mods and packwiz config..."
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue mods, config/packwiz-installer.toml
}

try {
    Install-PackwizBootstrap (Get-Location).Path

    Write-Host "Syncing modpack via packwiz..."
    $packwizArgs = @("-jar", "packwiz-installer-bootstrap.jar", "-g", "-s", $resolvedPackwizSide)
    # Splitting on one literal space would pass java an empty argument for every
    # doubled space in the string.
    if ($resolvedPackwizExtraFlags) { $packwizArgs += @($resolvedPackwizExtraFlags -split '\s+' | Where-Object { $_ }) }
    $packwizArgs += $resolvedPackwizUrl

    & java @packwizArgs
    if ($LASTEXITCODE -ne 0) { throw "packwiz-installer-bootstrap failed with exit code $LASTEXITCODE" }
}
catch {
    if ($Strict) {
        throw
    }
    Write-Warning "Pack sync failed: $($_.Exception.Message)"
}
