#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "https://thunder.john.rooney.scot/pack.toml",
    [string]$PackwizSide = "server",
    [string]$PackwizExtraFlags = "",
    [switch]$CleanInstall,
    [string]$ServerJarFile = "server.jar",
    [int]$VoicePort = 24454
)

$ErrorActionPreference = "Stop"

if ($Dir) { Set-Location $Dir }

if ($PackwizSide -notin @("server", "both")) {
    throw "PACKWIZ_SIDE must be 'server' or 'both'."
}

if ($PackwizUrl -match "\s") {
    throw "PACKWIZ_URL must not contain whitespace."
}

if ($PackwizExtraFlags -match "[;|&`$()<>{}]" -or $PackwizExtraFlags -match "[\r\n]") {
    throw "PACKWIZ_EXTRA_FLAGS contains unsupported characters."
}

if ($VoicePort -lt 0 -or $VoicePort -gt 65535) {
    throw "VOICE_PORT must be between 0 and 65535 (0 to disable)."
}

if ($CleanInstall) {
    Write-Host "Clean install - wiping mods and packwiz config..."
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue mods, config/packwiz-installer.toml
}

Write-Host "Syncing modpack via packwiz..."
$packwizArgs = @("-jar", "packwiz-installer-bootstrap.jar", "-g", "-s", $PackwizSide)
if ($PackwizExtraFlags) { $packwizArgs += $PackwizExtraFlags -split " " }
$packwizArgs += $PackwizUrl
& java @packwizArgs
if ($LASTEXITCODE -ne 0) { throw "packwiz-installer-bootstrap failed with exit code $LASTEXITCODE" }

if ($VoicePort -ne 0) {
    $voiceDir = Join-Path "config" "voicechat"
    if (-not (Test-Path $voiceDir)) { New-Item -ItemType Directory -Path $voiceDir -Force | Out-Null }
    Set-Content (Join-Path $voiceDir "voicechat-server.properties") "port=$VoicePort"
}

if (Test-Path "unix_args.txt") {
    & java -Xms128M "-XX:MaxRAMPercentage=95.0" "@unix_args.txt"
}
else {
    & java -Xms128M "-XX:MaxRAMPercentage=95.0" -jar $ServerJarFile
}
exit $LASTEXITCODE
