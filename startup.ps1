#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "https://packwiz.thunder.john.rooney.scot/pack.toml",
    [string]$PackwizSide = "server",
    [string]$PackwizExtraFlags = "",
    [switch]$SkipPackUpdate,
    [switch]$CleanInstall,
    [string]$ServerJarFile = "server.jar",
    [int]$VoicePort = 24454
)

$ErrorActionPreference = "Stop"

if ($Dir) { Set-Location $Dir }

function Get-JavaMajorVersion {
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        return $null
    }

    $versionOutput = & java -version 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
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

function Ensure-Java21 {
    $javaMajor = Get-JavaMajorVersion
    if ($javaMajor -eq "21") {
        return
    }

    if (Use-LocalJava21IfAvailable) {
        $javaMajor = Get-JavaMajorVersion
    }

    if ($javaMajor -ne "21") {
        $foundJava = if ($javaMajor) { $javaMajor } else { "none" }
        throw "Java 21 is required; found Java $foundJava."
    }
}

Ensure-Java21

if ($VoicePort -lt 0 -or $VoicePort -gt 65535) {
    throw "VOICE_PORT must be between 0 and 65535 (0 to disable)."
}

$skipByEnv = $env:PACKWIZ_SKIP_UPDATE -match '^(1|true|yes)$'
if ($SkipPackUpdate -or $skipByEnv) {
    if ($CleanInstall) {
        Write-Host "Clean install - wiping mods and packwiz config..."
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue mods, config/packwiz-installer.toml
    }
    Write-Host "Skipping packwiz sync (SkipPackUpdate/PACKWIZ_SKIP_UPDATE enabled)."
}
else {
    $updateScript = Join-Path $PSScriptRoot "update.ps1"
    if (-not (Test-Path $updateScript)) {
        throw "Could not find '$updateScript'."
    }

    & $updateScript `
        -PackwizUrl $PackwizUrl `
        -PackwizSide $PackwizSide `
        -PackwizExtraFlags $PackwizExtraFlags `
        -CleanInstall:$CleanInstall `
        -Strict
}

if ($VoicePort -ne 0) {
    $voiceDir = Join-Path "config" "voicechat"
    if (-not (Test-Path $voiceDir)) { New-Item -ItemType Directory -Path $voiceDir -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $voiceDir "voicechat-server.properties") -Value "port=$VoicePort" -Encoding ASCII
}

if (Test-Path "unix_args.txt") {
    $winArgs = (Get-Content "unix_args.txt") -replace "(?<=\.jar):", ";"
    Set-Content -LiteralPath "win_args.txt" -Value $winArgs -Encoding ASCII
    & java -Xms128M "-XX:MaxRAMPercentage=95.0" "@win_args.txt"
}
else {
    & java -Xms128M "-XX:MaxRAMPercentage=95.0" -jar $ServerJarFile
}
exit $LASTEXITCODE
