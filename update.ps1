#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "https://packwiz.thunder.john.rooney.scot/pack.toml",
    [string]$PackwizSide = "server",
    [string]$PackwizExtraFlags = "",
    [switch]$CleanInstall,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

if ($Dir) { Set-Location $Dir }

# Discover local JDK installed by install.ps1 if java is not on PATH
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    $localJdk = Get-ChildItem -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($localJdk) {
        $env:JAVA_HOME = $localJdk.FullName
        $env:PATH = "$($localJdk.FullName)\bin;$env:PATH"
        Write-Host "Using local JDK at $($localJdk.Name)"
    }
}

function Test-Truthy([string]$Value) {
    return $Value -match '^(1|true|yes)$'
}

if (Test-Truthy "$env:PACKWIZ_SKIP_UPDATE") {
    Write-Host "Skipping packwiz sync (PACKWIZ_SKIP_UPDATE enabled)."
    exit 0
}

if ($PackwizSide -notin @("client", "server", "both")) {
    throw "PACKWIZ_SIDE must be 'client', 'server', or 'both'."
}

if ($PackwizUrl -match "\s") {
    throw "PACKWIZ_URL must not contain whitespace."
}

if ($PackwizExtraFlags -match "[;|&`$()<>{}]" -or $PackwizExtraFlags -match "[\r\n]") {
    throw "PACKWIZ_EXTRA_FLAGS contains unsupported characters."
}

if ($CleanInstall) {
    Write-Host "Clean install - wiping mods and packwiz config..."
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue mods, config/packwiz-installer.toml
}

function Install-PackwizBootstrap {
    $bootstrapJar = Join-Path (Get-Location) "packwiz-installer-bootstrap.jar"
    if (Test-Path $bootstrapJar) {
        return
    }

    Write-Host "packwiz-installer-bootstrap.jar not found, downloading latest release..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/packwiz/packwiz-installer-bootstrap/releases/latest" -TimeoutSec 30
    $asset = $release.assets | Where-Object { $_.name -eq "packwiz-installer-bootstrap.jar" } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -like "*.jar" -and $_.name -notlike "*sources*.jar" -and $_.name -notlike "*javadoc*.jar" } | Select-Object -First 1
    }
    if (-not $asset) {
        throw "Could not resolve packwiz-installer-bootstrap release asset."
    }

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $bootstrapJar -TimeoutSec 120
}

try {
    Install-PackwizBootstrap

    Write-Host "Syncing modpack via packwiz..."
    $packwizArgs = @("-jar", "packwiz-installer-bootstrap.jar", "-g", "-s", $PackwizSide)
    if ($PackwizExtraFlags) { $packwizArgs += $PackwizExtraFlags -split " " }
    $packwizArgs += $PackwizUrl

    & java @packwizArgs
    if ($LASTEXITCODE -ne 0) { throw "packwiz-installer-bootstrap failed with exit code $LASTEXITCODE" }
}
catch {
    if ($Strict) {
        throw
    }
    Write-Warning "Pack sync failed: $($_.Exception.Message)"
}
