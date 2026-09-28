#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = ".",
    [string]$McVersion = "",
    [string]$ForgeVersion = "",
    [string]$ServerJarFile = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# functions.ps1 sits beside this script when fetched standalone, or one level
# up when this script is run from the repo tools/ directory.
$functionsScript = @(
    (Join-Path $PSScriptRoot "functions.ps1"),
    (Join-Path (Split-Path -Parent $PSScriptRoot) "functions.ps1")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $functionsScript) {
    throw "functions.ps1 not found next to or above this script. Download it from the same release as install.ps1."
}
. $functionsScript

Set-Location $Dir

$McVersion = Resolve-StringSetting $McVersion $env:MC_VERSION "1.20.1"
$ForgeVersion = Resolve-StringSetting $ForgeVersion $env:FORGE_VERSION "47.4.13"
$ServerJarFile = Resolve-StringSetting $ServerJarFile $env:SERVER_JARFILE "server.jar"

if ($McVersion -notmatch '^\d+\.\d+(\.\d+)?$') {
    throw "MC_VERSION must be in the form x.y or x.y.z."
}

if ($ForgeVersion -notmatch '^\d+(\.\d+)*$') {
    throw "FORGE_VERSION must contain only digits and dots."
}

Assert-ServerJarFile "SERVER_JARFILE" $ServerJarFile

Confirm-SupportedJava

Install-PackwizBootstrap (Get-Location).Path

# run.sh and run.bat come straight back from the installer, so clearing them is
# only tidiness. user_jvm_args.txt does not: the installer keeps an existing one
# across a reinstall, precisely so an operator's own flags survive, and
# startup.ps1 launches with it when it is there.
Remove-Item -Force -ErrorAction SilentlyContinue unix_args.txt, win_args.txt, run.sh, run.bat

Write-Host "Installing Forge ${McVersion}-${ForgeVersion}..."
$installerJar = "forge-${McVersion}-${ForgeVersion}-installer.jar"
try {
    Invoke-Download "https://maven.minecraftforge.net/net/minecraftforge/forge/${McVersion}-${ForgeVersion}/forge-${McVersion}-${ForgeVersion}-installer.jar" $installerJar
    & java -jar $installerJar --installServer
    if ($LASTEXITCODE -ne 0) { throw "Forge installer failed with exit code $LASTEXITCODE" }

    # The installer writes both argument files. win_args.txt is the one
    # startup.ps1 launches with; unix_args.txt is kept alongside it so the same
    # folder still works with startup.sh.
    $forgeDir = "libraries/net/minecraftforge/forge/${McVersion}-${ForgeVersion}"
    $winArgsFile = "${forgeDir}/win_args.txt"
    $unixArgsFile = "${forgeDir}/unix_args.txt"
    if (Test-Path $winArgsFile) {
        Copy-Item $winArgsFile "win_args.txt" -Force
        if (Test-Path $unixArgsFile) {
            Copy-Item $unixArgsFile "unix_args.txt" -Force
        }
        Write-Host "Copied win_args.txt for Forge ${McVersion}-${ForgeVersion}"
    }
    elseif (-not (Test-Path $ServerJarFile)) {
        throw "Forge installation produced neither win_args.txt nor ${ServerJarFile}."
    }
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $installerJar, "${installerJar}.log"
}

$packwizUrl = Resolve-StringSetting "" $env:PACKWIZ_URL "https://packwiz.thunder.john.rooney.scot/pack.toml"
$packwizSide = Resolve-StringSetting "" $env:PACKWIZ_SIDE "server"

if ($packwizSide -notin @("server", "both")) {
    throw "PACKWIZ_SIDE must be 'server' or 'both'."
}

Assert-PackwizUrl "PACKWIZ_URL" $packwizUrl

Write-Host "Syncing modpack via packwiz..."
& java -jar packwiz-installer-bootstrap.jar -g -s $packwizSide $packwizUrl
if ($LASTEXITCODE -ne 0) { throw "packwiz-installer-bootstrap failed with exit code $LASTEXITCODE" }

Write-Host "Server installation complete."
