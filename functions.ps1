#Requires -Version 5.1

# Shared by startup.ps1, tools/install.ps1 and tools/update.ps1, as functions.sh
# is shared by their shell counterparts. install.ps1 is fetched standalone, so
# this file is a release asset beside it as well as part of the pack.

# One try and three retries, a two second pause between them, which is what
# curl --retry 3 --retry-delay 2 does for the shell scripts. Windows
# PowerShell 5.1 has no retry parameter of its own.
function Invoke-WithRetry([string]$Description, [scriptblock]$Action) {
    for ($attempt = 1; ; $attempt++) {
        try {
            return & $Action
        }
        catch {
            if ($attempt -ge 4) {
                throw
            }

            Write-Host "$Description failed, retrying in 2 seconds: $($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
}

# The progress bar is off because on 5.1 drawing it slows a large download by an
# order of magnitude. UseBasicParsing because without it 5.1 reaches for the
# Internet Explorer engine, which Server Core does not have.
function Invoke-Download([string]$Uri, [string]$OutFile, [int]$TimeoutSec = 120) {
    $ProgressPreference = "SilentlyContinue"
    Invoke-WithRetry "Downloading $Uri" {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing
    }
}

function Test-FileSha256([string]$Path, [string]$ExpectedSha256) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $ExpectedSha256
}

# Pinned by version and hash rather than fetched from releases/latest, because
# the jar runs with java -jar on every player machine and every server boot.
# v0.0.3 has been the only release since 2020. What it runs is a different
# matter: it still updates packwiz-installer itself on each run unless told not
# to, which is how packwiz is meant to work, so this pins the first link of the
# chain and not the whole of it.
function Install-PackwizBootstrap([string]$Directory) {
    $url = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar"
    $sha256 = "a8fbb24dc604278e97f4688e82d3d91a318b98efc08d5dbfcbcbcab6443d116c"
    $jar = Join-Path $Directory "packwiz-installer-bootstrap.jar"

    if (Test-FileSha256 $jar $sha256) {
        return
    }

    Write-Host "Fetching packwiz-installer-bootstrap v0.0.3..."
    $download = "$jar.download"
    try {
        Invoke-Download $url $download
        if (-not (Test-FileSha256 $download $sha256)) {
            throw "packwiz-installer-bootstrap.jar did not match its pinned SHA-256, so it was not used."
        }
        Move-Item -LiteralPath $download -Destination $jar -Force
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $download
    }
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

    $env:JAVA_HOME = $localJava.FullName
    $env:PATH = "$($localJava.FullName)\bin;$env:PATH"
    Write-Host "Using local Java 21 at $($localJava.FullName)"
    return $true
}

# Follows the newest Temurin 21 rather than pinning one, because a JRE is where
# security fixes land, and checks the archive against the checksum Adoptium
# publishes for it. The link has to point into Adoptium's own GitHub releases,
# so a bad answer from the API cannot send the download somewhere else along
# with a checksum to match.
function Install-Temurin21 {
    Write-Host "Installing Temurin 21..."
    $arch = Get-TemurinArch
    $javaZip = "temurin-21-$arch.zip"

    try {
        $assets = Invoke-WithRetry "Asking Adoptium for the newest Temurin 21" {
            Invoke-RestMethod -Uri "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$arch&image_type=jre&os=windows&vendor=eclipse" -TimeoutSec 30
        }
        $package = ($assets | Select-Object -First 1).binary.package
        if (-not $package -or -not $package.checksum -or $package.link -notlike "https://github.com/adoptium/*") {
            throw "Adoptium did not return a usable Temurin 21 download."
        }

        Invoke-Download $package.link $javaZip 300
        if (-not (Test-FileSha256 $javaZip $package.checksum)) {
            throw "$($package.name) did not match the checksum Adoptium publishes for it."
        }

        Expand-Archive -Path $javaZip -DestinationPath "." -Force
    }
    catch {
        throw "Failed to install Temurin 21: $_"
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $javaZip
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

function Confirm-SupportedJava {
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

function Resolve-StringSetting([string]$ArgumentValue, [string]$EnvValue, [string]$DefaultValue) {
    if ($ArgumentValue) {
        return $ArgumentValue
    }

    if ($EnvValue) {
        return $EnvValue
    }

    return $DefaultValue
}

# Over plaintext an attacker on the path controls the index and the hashes that
# index is checked against, so hash verification proves nothing about what ends
# up in mods/. The only host that legitimately serves the pack over http is the
# local one in tests/ and CI, and that sets PACKWIZ_ALLOW_INSECURE_URL to say
# so. A real install has no reason to.
function Assert-PackwizUrl([string]$Name, [string]$Value) {
    if ($Value -match "\s") {
        throw "$Name must not contain whitespace."
    }

    if ($Value -notlike "https://*" -and $env:PACKWIZ_ALLOW_INSECURE_URL -notmatch '^(1|true|yes)$') {
        throw "$Name must be an https:// URL. Set PACKWIZ_ALLOW_INSECURE_URL=1 to allow a plaintext host, which is only safe for a local test."
    }
}

# SERVER_JARFILE names a file in the server directory, not a path to one.
function Assert-ServerJarFile([string]$Name, [string]$Value) {
    if ($Value -notmatch '^[A-Za-z0-9._-]+\.jar$') {
        throw "$Name must be a simple .jar filename."
    }
}

# Operator-supplied flags reach a command line, so the allowlist is a deliberate
# floor: letters, numbers, spaces and the punctuation a JVM or packwiz flag
# actually needs.
function Assert-ExtraFlags([string]$Name, [string]$Value) {
    if ($Value -match '[^A-Za-z0-9.,/:=_+\- ]') {
        throw "$Name may only contain letters, numbers, spaces, and the characters . , / : = _ + -."
    }
}
