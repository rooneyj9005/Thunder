#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "",
    [string]$PackwizSide = "",
    [string]$PackwizExtraFlags = "",
    [switch]$AutoUpdate,
    [switch]$CleanInstall,
    [string]$ServerJarFile = "",
    [Nullable[int]]$VoicePort = $null,
    [string]$EnableVoiceChat = "",
    [Nullable[int]]$MemoryMiB = $null,
    [Nullable[int]]$JvmMemoryMiB = $null
)

$ErrorActionPreference = "Stop"

if ($Dir) { Set-Location $Dir }

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

function Resolve-NonNegativeMiB([string]$Name, [Nullable[int]]$ArgumentValue, [string]$EnvValue) {
    if ($null -ne $ArgumentValue) {
        if ($ArgumentValue -lt 0) {
            throw "$Name must be a non-negative integer in MiB."
        }

        return $ArgumentValue
    }

    if (-not $EnvValue) {
        return 0
    }

    if ($EnvValue -notmatch '^\d+$') {
        throw "$Name must be a non-negative integer in MiB."
    }

    return [int]$EnvValue
}

function Get-AutomaticHeapMiB([int]$TotalMemoryMiB) {
    $reserveMiB = [int][Math]::Floor($TotalMemoryMiB / 20)
    if ($reserveMiB -lt 256) {
        $reserveMiB = 256
    }
    elseif ($reserveMiB -gt 1024) {
        $reserveMiB = 1024
    }

    $heapMiB = $TotalMemoryMiB - $reserveMiB
    if ($heapMiB -lt 512) {
        throw "--memory $TotalMemoryMiB does not leave enough room for a safe heap after JVM overhead. Use at least 768 MiB or set -JvmMemoryMiB explicitly."
    }

    return $heapMiB
}

function Get-JavaMemoryArgs([int]$ResolvedMemoryMiB, [int]$ResolvedJvmMemoryMiB) {
    if ($ResolvedJvmMemoryMiB -gt 0) {
        if ($ResolvedMemoryMiB -gt 0 -and $ResolvedJvmMemoryMiB -ge $ResolvedMemoryMiB) {
            Write-Warning "-JvmMemoryMiB $ResolvedJvmMemoryMiB is at least the full advertised server memory of $ResolvedMemoryMiB MiB. This leaves no headroom for native JVM or container overhead."
        }

        Write-Host "Using exact JVM heap of $ResolvedJvmMemoryMiB MiB."
        return @("-Xms$($ResolvedJvmMemoryMiB)M", "-Xmx$($ResolvedJvmMemoryMiB)M")
    }

    if ($ResolvedMemoryMiB -gt 0) {
        $heapMiB = Get-AutomaticHeapMiB $ResolvedMemoryMiB
        Write-Host "Using automatic JVM heap of $heapMiB MiB from $ResolvedMemoryMiB MiB total server memory."
        return @("-Xms$($heapMiB)M", "-Xmx$($heapMiB)M")
    }

    return @("-Xms128M", "-XX:MaxRAMPercentage=95.0")
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

function Resolve-BooleanSetting([string]$Name, [string]$ArgumentValue, [string]$EnvValue, [string]$DefaultValue) {
    $candidate = if ($ArgumentValue) {
        $ArgumentValue
    }
    elseif ($EnvValue) {
        $EnvValue
    }
    else {
        $DefaultValue
    }

    switch -Regex ($candidate) {
        '^(1|true|yes)$' { return $true }
        '^(0|false|no)$' { return $false }
        default { throw "$Name must be one of: true, false, 1, 0, yes, or no." }
    }
}

function Resolve-NonNegativeSetting([string]$Name, [Nullable[int]]$ArgumentValue, [string]$EnvValue, [int]$DefaultValue) {
    if ($null -ne $ArgumentValue) {
        if ($ArgumentValue -lt 0) {
            throw "$Name must be a non-negative integer."
        }

        return $ArgumentValue
    }

    if (-not $EnvValue) {
        return $DefaultValue
    }

    if ($EnvValue -notmatch '^\d+$') {
        throw "$Name must be a non-negative integer."
    }

    return [int]$EnvValue
}

$resolvedMemoryMiB = Resolve-NonNegativeMiB "--memory" $MemoryMiB $env:SERVER_MEMORY
$resolvedJvmMemoryMiB = Resolve-NonNegativeMiB "--jvm-memory" $JvmMemoryMiB $env:JVM_MEMORY
$resolvedPackwizUrl = Resolve-StringSetting $PackwizUrl $env:PACKWIZ_URL "https://packwiz.thunder.john.rooney.scot/pack.toml"
$resolvedPackwizSide = Resolve-StringSetting $PackwizSide $env:PACKWIZ_SIDE "server"
$resolvedPackwizExtraFlags = Resolve-StringSetting $PackwizExtraFlags $env:PACKWIZ_EXTRA_FLAGS ""
$resolvedServerJarFile = Resolve-StringSetting $ServerJarFile $env:SERVER_JARFILE "server.jar"
$resolvedVoicePort = Resolve-NonNegativeSetting "VOICE_PORT" $VoicePort $env:VOICE_PORT 24454
$resolvedCleanInstall = $CleanInstall -or ($env:CLEAN_INSTALL -match '^(1|true|yes)$')
$javaMemoryArgs = Get-JavaMemoryArgs $resolvedMemoryMiB $resolvedJvmMemoryMiB
# Named differently from the $EnableVoiceChat parameter on purpose: variable names
# are case-insensitive, and assigning a boolean to that [string] parameter would
# turn it into the truthy string "False".
$voiceChatEnabled = Resolve-BooleanSetting "ENABLE_VOICE_CHAT" $EnableVoiceChat $env:ENABLE_VOICE_CHAT "true"

if ($resolvedVoicePort -gt 65535) {
    throw "VOICE_PORT must be between 0 and 65535 (0 to disable)."
}

$autoByEnv = $env:PACKWIZ_AUTO_UPDATE -match '^(1|true|yes)$'
if ($AutoUpdate -or $autoByEnv) {
    $updateScript = Join-Path (Join-Path $PSScriptRoot "tools") "update.ps1"
    if (-not (Test-Path $updateScript)) {
        throw "Could not find '$updateScript'."
    }

    # update.ps1 defaults -Dir to its own folder, which is tools/, so the
    # server directory has to be passed explicitly.
    & $updateScript `
        -Dir (Get-Location).Path `
        -PackwizUrl $resolvedPackwizUrl `
        -PackwizSide $resolvedPackwizSide `
        -PackwizExtraFlags $resolvedPackwizExtraFlags `
        -CleanInstall:$resolvedCleanInstall `
        -Strict
}
else {
    if ($resolvedCleanInstall) {
        Write-Host "Clean install - wiping mods and packwiz config..."
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue mods, config/packwiz-installer.toml
    }
    Write-Host "Skipping packwiz sync. Set PACKWIZ_AUTO_UPDATE=true to sync on every start."
}

# Java reads .properties files as ISO-8859-1, so the same encoding is used here
# to round-trip every byte of the lines that are not being changed.
$propertiesEncoding = [System.Text.Encoding]::GetEncoding(28591)

# .NET file calls resolve relative paths against the process directory, which
# Set-Location does not change, so paths are made absolute from the PowerShell
# location first.
function Resolve-AbsolutePath([string]$Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-PropertiesLines([string]$Path) {
    $absolutePath = Resolve-AbsolutePath $Path
    if (Test-Path -LiteralPath $absolutePath) {
        return @([System.IO.File]::ReadAllLines($absolutePath, $propertiesEncoding))
    }

    return @()
}

# Rewrites one key in a Java .properties file and keeps every other line,
# comments included, exactly as it was. A missing file is created with just
# this key; the mod fills in its defaults on the next load.
function Set-PropertiesKey([string]$Path, [string]$Key, [string]$Value) {
    $lines = @(Get-PropertiesLines $Path | Where-Object { -not $_.StartsWith("$Key=") })
    $lines += "$Key=$Value"
    [System.IO.File]::WriteAllLines((Resolve-AbsolutePath $Path), [string[]]$lines, $propertiesEncoding)
}

function Test-PropertiesKeyEquals([string]$Path, [string]$Key, [string]$Value) {
    return (Get-PropertiesLines $Path) -contains "$Key=$Value"
}

# Simple Voice Chat keeps its server settings in a .properties file that the mod
# rewrites with every key on load. Only the keys below are touched, so operator
# edits to the rest of the file survive a restart. Disabling voice chat binds the
# UDP listener to loopback instead of deleting the file, which would only make
# the mod regenerate its defaults and listen on every interface again.
$voiceDir = Join-Path "config" "voicechat"
$voiceConfigFile = Join-Path $voiceDir "voicechat-server.properties"
if (-not (Test-Path $voiceDir)) { New-Item -ItemType Directory -Path $voiceDir -Force | Out-Null }

if ($voiceChatEnabled -and $resolvedVoicePort -ne 0) {
    Set-PropertiesKey $voiceConfigFile "port" "$resolvedVoicePort"
    if (Test-PropertiesKeyEquals $voiceConfigFile "bind_address" "127.0.0.1") {
        Write-Host "Voice chat re-enabled. Clearing the loopback bind_address so it listens on every interface again."
        Set-PropertiesKey $voiceConfigFile "bind_address" ""
    }
    Write-Host "Simple Voice Chat listens on UDP port $resolvedVoicePort."
}
else {
    Set-PropertiesKey $voiceConfigFile "bind_address" "127.0.0.1"
    Write-Host "Voice chat disabled. Simple Voice Chat is bound to 127.0.0.1 and is not reachable from outside."
}

# The Forge installer writes win_args.txt beside unix_args.txt. install.ps1
# copies it to the server root; older installs only have unix_args.txt at the
# root, so fall back to the copy inside libraries/ before giving up.
function Resolve-ForgeArgsFile {
    if (Test-Path -LiteralPath "win_args.txt") {
        return "win_args.txt"
    }

    if (-not (Test-Path -LiteralPath "unix_args.txt")) {
        return $null
    }

    $candidates = @(Get-ChildItem -Path "libraries/net/minecraftforge/forge/*/win_args.txt" -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 1) {
        Copy-Item -LiteralPath $candidates[0].FullName -Destination "win_args.txt" -Force
        Write-Host "Copied win_args.txt from $($candidates[0].DirectoryName)."
        return "win_args.txt"
    }

    throw "unix_args.txt is present but win_args.txt is not, and $($candidates.Count) Forge versions are installed under libraries/. Re-run tools/install.ps1 to repair the install."
}

$forgeArgsFile = Resolve-ForgeArgsFile
if ($forgeArgsFile) {
    & java @javaMemoryArgs "@$forgeArgsFile"
}
else {
    & java @javaMemoryArgs -jar $resolvedServerJarFile
}
exit $LASTEXITCODE
