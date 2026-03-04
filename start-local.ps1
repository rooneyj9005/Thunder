#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "",
    [string]$PackwizSide = "server",
    [string]$PackwizExtraFlags = "",
    [switch]$CleanInstall,
    [string]$ServerJarFile = "server.jar",
    [int]$VoicePort = 24454
)

$ErrorActionPreference = "Stop"

if ($Dir) { Set-Location $Dir }

$javaCmd = Get-Command java -ErrorAction SilentlyContinue
if (-not $javaCmd) {
    $localJdk = Get-ChildItem -Path $PSScriptRoot -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $localJdk) {
        $localJdk = Get-ChildItem -Path (Get-Location) -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($localJdk) {
        $env:JAVA_HOME = $localJdk.FullName
        $env:PATH = "$($localJdk.FullName)\\bin;$env:PATH"
        Write-Host "Using local JDK: $($localJdk.FullName)"
    }
}

if (-not $PackwizUrl) {
    $localPackToml = Join-Path $PSScriptRoot "..\source\pack.toml"
    if (-not (Test-Path $localPackToml)) {
        throw "Could not find local source pack at '$localPackToml'. Pass -PackwizUrl explicitly."
    }

    $resolvedPackToml = (Resolve-Path $localPackToml).Path.Replace("\", "/")
    $PackwizUrl = "file:///$resolvedPackToml"
}

Write-Host "Using pack URL: $PackwizUrl"

& (Join-Path $PSScriptRoot "startup.ps1") `
    -PackwizUrl $PackwizUrl `
    -PackwizSide $PackwizSide `
    -PackwizExtraFlags $PackwizExtraFlags `
    -CleanInstall:$CleanInstall `
    -ServerJarFile $ServerJarFile `
    -VoicePort $VoicePort
