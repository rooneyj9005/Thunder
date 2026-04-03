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

$defaultDir = if ($Dir) {
    $Dir
}
elseif ($PSScriptRoot) {
    $PSScriptRoot
}
elseif ($PSCommandPath) {
    Split-Path -Parent $PSCommandPath
}
else {
    (Get-Location).Path
}

Set-Location $defaultDir

function Get-JavaMajorVersionFromCommand([string]$JavaCommandPath) {
    if (-not $JavaCommandPath -or -not (Test-Path -LiteralPath $JavaCommandPath -PathType Leaf)) {
        return $null
    }

    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

    try {
        $process = Start-Process -FilePath $JavaCommandPath -ArgumentList "-version" -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

        if ($process.ExitCode -ne 0) {
            return $null
        }

        $versionOutput = @()
        if (Test-Path $stderrPath) {
            $versionOutput += Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
        }
        if (Test-Path $stdoutPath) {
            $versionOutput += Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
        }

        $firstLine = $versionOutput | Select-Object -First 1
        if ($firstLine -match '"(?<version>[^"]+)"') {
            $parts = $Matches.version.Split(".")
            if ($parts[0] -eq "1" -and $parts.Length -gt 1) {
                return $parts[1]
            }
            return $parts[0]
        }

        return $null
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath
    }
}

function Get-JavaMajorVersion {
    $javaCommand = Get-Command java -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $javaCommand) {
        return $null
    }

    return Get-JavaMajorVersionFromCommand $javaCommand.Source
}

function Test-SupportedJavaVersion([string]$Version) {
    return $Version -in @("17", "21")
}

function Get-TemurinArch {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    switch ($arch) {
        "X64" { return "x64" }
        "Arm64" { return "aarch64" }
        default { throw "Unsupported Windows architecture for Temurin 21: $arch." }
    }
}

function Use-LauncherJavaIfAvailable {
    if (-not $env:INST_JAVA) {
        return $false
    }

    $launcherJava = $env:INST_JAVA.Trim('"')
    $launcherMajor = Get-JavaMajorVersionFromCommand $launcherJava
    if (-not (Test-SupportedJavaVersion $launcherMajor)) {
        return $false
    }

    $launcherBinDir = Split-Path -Parent $launcherJava
    $launcherHome = Split-Path -Parent $launcherBinDir
    $env:JAVA_HOME = $launcherHome
    $env:PATH = "$launcherBinDir;$env:PATH"
    Write-Host "Using launcher Java at $launcherJava"
    return $true
}

function Use-LocalJava21IfAvailable {
    $localJava = Get-ChildItem -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "jdk-21*" -or $_.Name -like "jre-21*"
    } | Select-Object -First 1

    if (-not $localJava) {
        return $false
    }

    $env:JAVA_HOME = $localJava.FullName
    $env:PATH = "$($localJava.FullName)\bin;$env:PATH"
    Write-Host "Using local Java 21 at $($localJava.FullName)"
    return $true
}

function Install-Temurin21 {
    Write-Host "Installing Temurin 21..."
    $arch = Get-TemurinArch
    $javaZip = "temurin-21-$arch.zip"
    try {
        Invoke-WebRequest -Uri "https://api.adoptium.net/v3/binary/latest/21/ga/windows/$arch/jre/hotspot/normal/eclipse" -OutFile $javaZip -TimeoutSec 300
        Expand-Archive -Path $javaZip -DestinationPath "." -Force
        Remove-Item $javaZip
    }
    catch {
        Remove-Item -Force -ErrorAction SilentlyContinue $javaZip
        throw "Failed to download Temurin 21: $_"
    }

    $jdkDir = Get-ChildItem -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "jdk-21*" -or $_.Name -like "jre-21*"
    } | Select-Object -First 1
    if (-not $jdkDir) {
        throw "Temurin 21 archive did not contain an expected jdk-21* or jre-21* directory."
    }

    $env:JAVA_HOME = $jdkDir.FullName
    $env:PATH = "$($jdkDir.FullName)\bin;$env:PATH"
    Write-Host "Installed Temurin 21 to $($jdkDir.FullName)"
}

function Ensure-SupportedJava {
    if (Use-LauncherJavaIfAvailable) {
        return
    }

    $javaMajor = Get-JavaMajorVersion
    if (Test-SupportedJavaVersion $javaMajor) {
        return
    }

    if (Use-LocalJava21IfAvailable) {
        $javaMajor = Get-JavaMajorVersion
    }

    if (-not (Test-SupportedJavaVersion $javaMajor)) {
        if ($javaMajor) {
            Write-Host "Java $javaMajor found. Switching to Temurin 21."
        }
        else {
            Write-Host "No supported Java runtime found locally. Installing Temurin 21."
        }

        Install-Temurin21
        $javaMajor = Get-JavaMajorVersion
    }

    if ($javaMajor -ne "21") {
        $foundJava = if ($javaMajor) { $javaMajor } else { "none" }
        throw "Java 17 or Java 21 is required; found Java $foundJava."
    }
}

Ensure-SupportedJava

function Test-Truthy([string]$Value) {
    return $Value -match '^(1|true|yes)$'
}

function Resolve-StringSetting([string]$ArgumentValue, [string]$EnvValue, [string]$DefaultValue) {
    if ($ArgumentValue) {
        return $ArgumentValue
    }

    if ($EnvValue) {
        return $EnvValue
    }

    return $DefaultValue
}

if (Test-Truthy "$env:PACKWIZ_SKIP_UPDATE") {
    Write-Host "Skipping packwiz sync (PACKWIZ_SKIP_UPDATE enabled)."
    exit 0
}

$resolvedPackwizUrl = Resolve-StringSetting $PackwizUrl $env:PACKWIZ_URL "https://packwiz.thunder.john.rooney.scot/pack.toml"
$resolvedPackwizSide = Resolve-StringSetting $PackwizSide $env:PACKWIZ_SIDE "server"
$resolvedPackwizExtraFlags = Resolve-StringSetting $PackwizExtraFlags $env:PACKWIZ_EXTRA_FLAGS ""
$resolvedCleanInstall = $CleanInstall -or (Test-Truthy "$env:CLEAN_INSTALL")

if ($resolvedPackwizSide -notin @("server", "both")) {
    throw "PACKWIZ_SIDE must be 'server' or 'both'."
}

if ($resolvedPackwizUrl -match "\s") {
    throw "PACKWIZ_URL must not contain whitespace."
}

if ($resolvedPackwizExtraFlags -match '[^A-Za-z0-9.,/:=_+\- ]') {
    throw "PACKWIZ_EXTRA_FLAGS may only contain letters, numbers, spaces, and the characters . , / : = _ + -."
}

if ($resolvedCleanInstall) {
    Write-Host "Clean install - wiping mods and packwiz config..."
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue mods, config/packwiz-installer.toml
}

function Install-PackwizBootstrap {
    $bootstrapJar = Join-Path (Get-Location) "packwiz-installer-bootstrap.jar"
    if (Test-Path $bootstrapJar) {
        return
    }

    Write-Host "packwiz-installer-bootstrap.jar not found, downloading latest release..."
    Invoke-WebRequest -Uri "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar" -OutFile $bootstrapJar -TimeoutSec 120
}

try {
    Install-PackwizBootstrap

    Write-Host "Syncing modpack via packwiz..."
    $packwizArgs = @("-jar", "packwiz-installer-bootstrap.jar", "-g", "-s", $resolvedPackwizSide)
    if ($resolvedPackwizExtraFlags) { $packwizArgs += $resolvedPackwizExtraFlags -split " " }
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
