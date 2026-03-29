#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = ".",
    [string]$ModLoader = "forge",
    [string]$McVersion = "1.20.1",
    [string]$ForgeVersion = "",
    [string]$ServerJarFile = "server.jar"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Set-Location $Dir

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
        Remove-Item -Force -ErrorAction SilentlyContinue unix_args.txt, user_jvm_args.txt, run.sh, run.bat

        $resolvedVersion = $ForgeVersion
        if (-not $resolvedVersion) {
            $promos = Invoke-RestMethod -Uri "https://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json" -TimeoutSec 30
            $resolvedVersion = $promos.promos."${McVersion}-recommended"
            if (-not $resolvedVersion) { $resolvedVersion = $promos.promos."${McVersion}-latest" }
            if (-not $resolvedVersion) {
                Write-Error "No Forge version found for Minecraft ${McVersion}."
                exit 1
            }
        }

        Write-Host "Installing Forge ${McVersion}-${resolvedVersion}..."
        $installerJar = "forge-${McVersion}-${resolvedVersion}-installer.jar"
        try {
            Invoke-WebRequest -Uri "https://maven.minecraftforge.net/net/minecraftforge/forge/${McVersion}-${resolvedVersion}/forge-${McVersion}-${resolvedVersion}-installer.jar" -OutFile $installerJar -TimeoutSec 120
            & java -jar $installerJar --installServer
            if ($LASTEXITCODE -ne 0) { throw "Forge installer failed with exit code $LASTEXITCODE" }

            $argsFile = "libraries/net/minecraftforge/forge/${McVersion}-${resolvedVersion}/unix_args.txt"
            if (Test-Path $argsFile) {
                Copy-Item $argsFile "unix_args.txt" -Force
                Write-Host "Copied unix_args.txt for Forge ${McVersion}-${resolvedVersion}"
            }
            elseif (-not (Test-Path $ServerJarFile)) {
                Write-Error "Forge installation produced neither unix_args.txt nor ${ServerJarFile}."
                exit 1
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
        Write-Error "Unknown modloader '${ModLoader}'. Expected: forge, fabric, or quilt."
        exit 1
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

Write-Host "Syncing modpack via packwiz..."
& java -jar packwiz-installer-bootstrap.jar -g -s $packwizSide $packwizUrl
if ($LASTEXITCODE -ne 0) { throw "packwiz-installer-bootstrap failed with exit code $LASTEXITCODE" }

Write-Host "Server installation complete."
