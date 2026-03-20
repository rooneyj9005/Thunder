#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "https://thunder.john.rooney.scot/pack.toml",
    [string]$PackwizSide = "server",
    [string]$PackwizExtraFlags = "",
    [switch]$SkipPackUpdate,
    [switch]$CleanInstall,
    [string]$ServerJarFile = "server.jar",
    [int]$VoicePort = 24454
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
    Set-Content (Join-Path $voiceDir "voicechat-server.properties") "port=$VoicePort"
}

if (Test-Path "unix_args.txt") {
    $winArgs = (Get-Content "unix_args.txt") -replace "(?<=\.jar):", ";"
    Set-Content "win_args.txt" $winArgs
    & java -Xms128M "-XX:MaxRAMPercentage=95.0" "@win_args.txt"
}
else {
    & java -Xms128M "-XX:MaxRAMPercentage=95.0" -jar $ServerJarFile
}
exit $LASTEXITCODE
