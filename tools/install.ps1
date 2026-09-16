#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = ".",
    [string]$ModLoader = "",
    [string]$McVersion = "",
    [string]$ForgeVersion = "",
    [string]$ServerJarFile = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Set-Location $Dir

function Resolve-StringSetting([string]$ArgumentValue, [string]$EnvValue, [string]$DefaultValue) {
    if ($ArgumentValue) {
        return $ArgumentValue
    }

    if ($EnvValue) {
        return $EnvValue
    }

    return $DefaultValue
}

$ModLoader = Resolve-StringSetting $ModLoader $env:MODLOADER "forge"
$McVersion = Resolve-StringSetting $McVersion $env:MC_VERSION "1.20.1"
$ForgeVersion = Resolve-StringSetting $ForgeVersion $env:FORGE_VERSION ""
$ServerJarFile = Resolve-StringSetting $ServerJarFile $env:SERVER_JARFILE "server.jar"

if ($ModLoader -notin @("forge", "fabric", "quilt")) {
    throw "MODLOADER must be 'forge', 'fabric', or 'quilt'."
}

if ($McVersion -notmatch '^\d+\.\d+(\.\d+)?$') {
    throw "MC_VERSION must be in the form x.y or x.y.z."
}

if ($ForgeVersion -and $ForgeVersion -notmatch '^\d+(\.\d+)*$') {
    throw "FORGE_VERSION must contain only digits and dots."
}

if ($ServerJarFile -notmatch '^[A-Za-z0-9._-]+\.jar$') {
    throw "SERVER_JARFILE must be a simple .jar filename."
}

function Get-JavaMajorVersion {
    $javaCommand = Get-Command java -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $javaCommand) {
        return $null
    }

    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

    try {
        $process = Start-Process -FilePath $javaCommand.Source -ArgumentList "-version" -NoNewWindow -Wait -PassThru `
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

        # Filter to the version line rather than taking the first. With
        # JAVA_TOOL_OPTIONS or _JAVA_OPTIONS set, java prints a "Picked up ..."
        # banner ahead of it, which carries no quoted version and made this
        # return $null on a perfectly good runtime.
        $versionLine = $versionOutput | Where-Object { $_ -match ' version "[^"]+"' } | Select-Object -First 1
        if ($versionLine -match ' version "(?<version>[^"]+)"') {
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

function Test-SupportedJavaVersion([string]$Version) {
    return $Version -in @("17", "21")
}

# The environment variables rather than RuntimeInformation.OSArchitecture: that
# member needs .NET Framework 4.7.1, which every modern host has, but it is not
# in the 5.1 profile PSScriptAnalyzer checks against and the warning is raised
# on every edit. A 32-bit PowerShell on 64-bit Windows reports x86 in
# PROCESSOR_ARCHITECTURE and the real architecture in PROCESSOR_ARCHITEW6432.
function Get-TemurinArch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        "AMD64" { return "x64" }
        "ARM64" { return "aarch64" }
        default { throw "Unsupported Windows architecture for Temurin 21: $arch." }
    }
}

function Use-LocalJava21IfAvailable {
    $localJava = Get-ChildItem -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "jdk-21*" -or $_.Name -like "jre-21*"
    } | Select-Object -First 1

    if (-not $localJava) {
        return $false
    }

    Write-Host "Using local Java 21 at $($localJava.FullName)"
    $env:JAVA_HOME = $localJava.FullName
    $env:PATH = "$($localJava.FullName)\bin;$env:PATH"
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

$javaMajor = Get-JavaMajorVersion
if (-not (Test-SupportedJavaVersion $javaMajor)) {
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

Write-Host "Fetching packwiz-installer-bootstrap..."
Invoke-WebRequest -Uri "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar" -OutFile "packwiz-installer-bootstrap.jar" -TimeoutSec 120
Write-Host "Downloaded packwiz-installer-bootstrap.jar"

if ($ModLoader -eq "forge" -and -not $ForgeVersion) {
    $ForgeVersion = "47.4.13"
}

switch ($ModLoader) {
    "forge" {
        # run.sh and run.bat come straight back from the installer, so clearing
        # them is only tidiness. user_jvm_args.txt does not: the installer keeps
        # an existing one across a reinstall, precisely so an operator's own
        # flags survive, and startup.ps1 launches with it when it is there.
        Remove-Item -Force -ErrorAction SilentlyContinue unix_args.txt, win_args.txt, run.sh, run.bat

        $resolvedVersion = $ForgeVersion
        if (-not $resolvedVersion) {
            $promos = Invoke-RestMethod -Uri "https://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json" -TimeoutSec 30
            $resolvedVersion = $promos.promos."${McVersion}-recommended"
            if (-not $resolvedVersion) { $resolvedVersion = $promos.promos."${McVersion}-latest" }
            if (-not $resolvedVersion) {
                throw "No Forge version found for Minecraft ${McVersion}."
            }
        }

        Write-Host "Installing Forge ${McVersion}-${resolvedVersion}..."
        $installerJar = "forge-${McVersion}-${resolvedVersion}-installer.jar"
        try {
            Invoke-WebRequest -Uri "https://maven.minecraftforge.net/net/minecraftforge/forge/${McVersion}-${resolvedVersion}/forge-${McVersion}-${resolvedVersion}-installer.jar" -OutFile $installerJar -TimeoutSec 120
            & java -jar $installerJar --installServer
            if ($LASTEXITCODE -ne 0) { throw "Forge installer failed with exit code $LASTEXITCODE" }

            # The installer writes both argument files. win_args.txt is the one
            # startup.ps1 launches with; unix_args.txt is kept alongside it so
            # the same folder still works with startup.sh.
            $forgeDir = "libraries/net/minecraftforge/forge/${McVersion}-${resolvedVersion}"
            $winArgsFile = "${forgeDir}/win_args.txt"
            $unixArgsFile = "${forgeDir}/unix_args.txt"
            if (Test-Path $winArgsFile) {
                Copy-Item $winArgsFile "win_args.txt" -Force
                if (Test-Path $unixArgsFile) {
                    Copy-Item $unixArgsFile "unix_args.txt" -Force
                }
                Write-Host "Copied win_args.txt for Forge ${McVersion}-${resolvedVersion}"
            }
            elseif (-not (Test-Path $ServerJarFile)) {
                throw "Forge installation produced neither win_args.txt nor ${ServerJarFile}."
            }
        }
        finally {
            Remove-Item -Force -ErrorAction SilentlyContinue $installerJar, "${installerJar}.log"
        }
    }

    "fabric" {
        $loaderVersion = $ForgeVersion
        if (-not $loaderVersion) {
            $loaders = Invoke-RestMethod -Uri "https://meta.fabricmc.net/v2/versions/loader" -TimeoutSec 30
            $loaderVersion = $loaders[0].version
        }
        $installerVersion = (Invoke-RestMethod -Uri "https://meta.fabricmc.net/v2/versions/installer" -TimeoutSec 30)[0].version

        Write-Host "Installing Fabric Loader ${loaderVersion} for Minecraft ${McVersion}..."
        $tmpJar = "${ServerJarFile}.tmp"
        try {
            Invoke-WebRequest -Uri "https://meta.fabricmc.net/v2/versions/loader/${McVersion}/${loaderVersion}/${installerVersion}/server/jar" -OutFile $tmpJar -TimeoutSec 120
            Move-Item $tmpJar $ServerJarFile -Force
        }
        catch {
            Remove-Item -Force -ErrorAction SilentlyContinue $tmpJar
            throw
        }
    }

    "quilt" {
        $loaderVersion = $ForgeVersion
        if (-not $loaderVersion) {
            $loaders = Invoke-RestMethod -Uri "https://meta.quiltmc.org/v3/versions/loader" -TimeoutSec 30
            $loaderVersion = $loaders[0].version
        }
        $installerVersion = (Invoke-RestMethod -Uri "https://meta.quiltmc.org/v3/versions/installer" -TimeoutSec 30)[0].version

        Write-Host "Installing Quilt Loader ${loaderVersion} for Minecraft ${McVersion}..."
        $tmpJar = "${ServerJarFile}.tmp"
        try {
            Invoke-WebRequest -Uri "https://meta.quiltmc.org/v3/versions/loader/${McVersion}/${loaderVersion}/${installerVersion}/server/jar" -OutFile $tmpJar -TimeoutSec 120
            Move-Item $tmpJar $ServerJarFile -Force
        }
        catch {
            Remove-Item -Force -ErrorAction SilentlyContinue $tmpJar
            throw
        }
    }

    default {
        throw "Unknown modloader '${ModLoader}'. Expected: forge, fabric, or quilt."
    }
}

$packwizUrl = if ($env:PACKWIZ_URL) { $env:PACKWIZ_URL } else { "https://packwiz.thunder.john.rooney.scot/pack.toml" }
$packwizSide = if ($env:PACKWIZ_SIDE) { $env:PACKWIZ_SIDE } else { "server" }

if ($packwizSide -notin @("server", "both")) {
    throw "PACKWIZ_SIDE must be 'server' or 'both'."
}

if ($packwizUrl -match "\s") {
    throw "PACKWIZ_URL must not contain whitespace."
}

# Over plaintext an attacker on the path controls the index and the hashes that
# index is checked against, so hash verification proves nothing about what ends
# up in mods/. The only host that legitimately serves the pack over http is the
# local one in tests/ and CI, and that sets PACKWIZ_ALLOW_INSECURE_URL to say
# so. A real install has no reason to.
if ($packwizUrl -notlike "https://*" -and $env:PACKWIZ_ALLOW_INSECURE_URL -notmatch '^(1|true|yes)$') {
    throw "PACKWIZ_URL must be an https:// URL. Set PACKWIZ_ALLOW_INSECURE_URL=1 to allow a plaintext host, which is only safe for a local test."
}

Write-Host "Syncing modpack via packwiz..."
& java -jar packwiz-installer-bootstrap.jar -g -s $packwizSide $packwizUrl
if ($LASTEXITCODE -ne 0) { throw "packwiz-installer-bootstrap failed with exit code $LASTEXITCODE" }

Write-Host "Server installation complete."
