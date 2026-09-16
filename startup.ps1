#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dir = "",
    [string]$PackwizUrl = "",
    [string]$PackwizSide = "",
    [string]$PackwizExtraFlags = "",
    [string]$JvmExtraFlags = "",
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

Confirm-SupportedJava

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

# Everything outside the heap shares the same machine. Metaspace alone runs 300
# to 500 MB on a pack this size, and then there is the code cache, G1's card
# tables and remembered sets, thread stacks, Netty's direct buffers and
# allocator fragmentation on top. Aikar's guidance is 1000 to 1500 MB; the old
# total/20 reserve left 307 MiB at the memory the egg recommends.
#
# The Linux side reads the cgroup limit before applying this, because there the
# kernel enforces a ceiling of its own. Windows has no equivalent, so this stays
# a plain formula and the two platforms diverge here deliberately.
function Get-AutomaticHeapMiB([int]$TotalMemoryMiB) {
    $reserveMiB = [int][Math]::Floor($TotalMemoryMiB * 15 / 100)
    if ($reserveMiB -lt 1024) {
        $reserveMiB = 1024
    }
    elseif ($reserveMiB -gt 2048) {
        $reserveMiB = 2048
    }

    $heapMiB = $TotalMemoryMiB - $reserveMiB
    if ($heapMiB -lt 512) {
        throw "$TotalMemoryMiB MiB does not leave enough room for a safe heap once $reserveMiB MiB is reserved for JVM overhead. Allocate at least 1536 MiB, or set -JvmMemoryMiB to pick the heap yourself."
    }

    return $heapMiB
}

# 0 means nothing said how much memory this server has, and the caller falls
# back to a percentage of what it finds.
function Get-ResolvedHeapMiB([int]$ResolvedMemoryMiB, [int]$ResolvedJvmMemoryMiB) {
    if ($ResolvedJvmMemoryMiB -gt 0) {
        if ($ResolvedMemoryMiB -gt 0 -and $ResolvedJvmMemoryMiB -ge $ResolvedMemoryMiB) {
            Write-Warning "-JvmMemoryMiB $ResolvedJvmMemoryMiB is at least the full advertised server memory of $ResolvedMemoryMiB MiB. This leaves no headroom for native JVM overhead."
        }

        Write-Host "Using exact JVM heap of $ResolvedJvmMemoryMiB MiB."
        return $ResolvedJvmMemoryMiB
    }

    if ($ResolvedMemoryMiB -gt 0) {
        $heapMiB = Get-AutomaticHeapMiB $ResolvedMemoryMiB
        Write-Host "Using automatic JVM heap of $heapMiB MiB, holding $($ResolvedMemoryMiB - $heapMiB) MiB of $ResolvedMemoryMiB MiB back for JVM overhead."
        return $heapMiB
    }

    return 0
}

function Get-JavaMemoryArgs([int]$HeapMiB) {
    if ($HeapMiB -gt 0) {
        return @("-Xms$($HeapMiB)M", "-Xmx$($HeapMiB)M")
    }

    # It was 95 per cent, which on a shared machine is a heap free to grow over
    # almost all of it, and paired with -Xms128M gave exactly the slow creep
    # towards the ceiling that AlwaysPreTouch is here to stop.
    return @("-XX:InitialRAMPercentage=75", "-XX:MaxRAMPercentage=75")
}

# Aikar's G1 flags, the reference tuning for a Minecraft server heap. Shipping
# them beats the JVM's defaults, which size the young generation for a
# throughput workload and pause a busy server long enough to be felt.
#
# AlwaysPreTouch is the one with teeth. It faults the whole heap in at boot
# instead of letting resident memory creep towards it over hours, so a heap that
# does not fit fails at start, in the open, rather than being killed quietly in
# the middle of a session.
function Get-JvmGcFlags([int]$HeapMiB) {
    # Aikar splits the tuning at 12 GB: a large heap gets a bigger young
    # generation, larger regions, and starts collecting later.
    if ($HeapMiB -ge 12288) {
        $newSizePercent = 40
        $maxNewSizePercent = 50
        $heapRegionSize = "16M"
        $reservePercent = 15
        $initiatingOccupancy = 20
    }
    else {
        $newSizePercent = 30
        $maxNewSizePercent = 40
        $heapRegionSize = "8M"
        $reservePercent = 20
        $initiatingOccupancy = 15
    }

    return @(
        "-XX:+UseG1GC",
        "-XX:+ParallelRefProcEnabled",
        "-XX:MaxGCPauseMillis=200",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:+DisableExplicitGC",
        "-XX:+AlwaysPreTouch",
        "-XX:+PerfDisableSharedMem",
        "-XX:G1NewSizePercent=$newSizePercent",
        "-XX:G1MaxNewSizePercent=$maxNewSizePercent",
        "-XX:G1HeapRegionSize=$heapRegionSize",
        "-XX:G1ReservePercent=$reservePercent",
        "-XX:InitiatingHeapOccupancyPercent=$initiatingOccupancy",
        "-XX:G1HeapWastePercent=5",
        "-XX:G1MixedGCCountTarget=4",
        "-XX:G1MixedGCLiveThresholdPercent=90",
        "-XX:G1RSetUpdatingPauseTimePercent=5",
        "-XX:SurvivorRatio=32",
        "-XX:MaxTenuringThreshold=1",
        "-Dusing.aikars.flags=https://mcflags.emc.gs",
        "-Daikars.new.flags=true",
        # An exhausted heap otherwise means the collector thrashing for as long
        # as it takes, which reads as a hang rather than a failure.
        "-XX:+ExitOnOutOfMemoryError"
    )
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
$resolvedJvmExtraFlags = Resolve-StringSetting $JvmExtraFlags $env:JVM_EXTRA_FLAGS ""
$resolvedHeapMiB = Get-ResolvedHeapMiB $resolvedMemoryMiB $resolvedJvmMemoryMiB
$javaMemoryArgs = Get-JavaMemoryArgs $resolvedHeapMiB
# Named differently from the $EnableVoiceChat parameter on purpose: variable names
# are case-insensitive, and assigning a boolean to that [string] parameter would
# turn it into the truthy string "False".
$voiceChatEnabled = Resolve-BooleanSetting "ENABLE_VOICE_CHAT" $EnableVoiceChat $env:ENABLE_VOICE_CHAT "true"

if ($resolvedVoicePort -gt 65535) {
    throw "VOICE_PORT must be between 0 and 65535 (0 to disable)."
}

# SERVER_JARFILE names a file in the server directory, not a path to one.
# tools/install.ps1 has always refused anything else; this is the same rule on
# the start path, which a standalone run can reach without going through it.
if ($resolvedServerJarFile -notmatch '^[A-Za-z0-9._-]+\.jar$') {
    throw "SERVER_JARFILE must be a simple .jar filename."
}

# Operator-supplied flags reach a command line, so the allowlist is a deliberate
# floor: letters, numbers, spaces and the punctuation a JVM flag actually needs.
if ($resolvedJvmExtraFlags -match '[^A-Za-z0-9.,/:=_+\- ]') {
    throw "JVM_EXTRA_FLAGS may only contain letters, numbers, spaces, and the characters . , / : = _ + -."
}

# A clean install is an install, so it syncs even when auto update is off.
# Refusing would strand every server built from an egg older than
# PACKWIZ_AUTO_UPDATE, whose panel has CLEAN_INSTALL and no way to add the new
# variable, leaving no setting available to get the server booting again.
#
# An absent PACKWIZ_AUTO_UPDATE means off here, and startup.sh deliberately
# reads it as on under --container. That asymmetry is the point: the container
# case is a Pterodactyl panel too old to carry the variable, whose servers
# synced on every boot and would otherwise never see a pack update again. There
# is no Windows panel and no --container on this side, so a run that does not
# set the variable is a person at a prompt, and they get the documented opt-in
# default.
$autoByEnv = $env:PACKWIZ_AUTO_UPDATE -match '^(1|true|yes)$'
if ($resolvedCleanInstall -and -not ($AutoUpdate -or $autoByEnv)) {
    Write-Host "Clean install requested, so syncing this start even though PACKWIZ_AUTO_UPDATE is off."
}
if ($AutoUpdate -or $autoByEnv -or $resolvedCleanInstall) {
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

# A modded world loaded with no mods either refuses to start or, worse, loads
# and strips every modded block on the first save. Stop before finding out which.
if ((Test-Path -LiteralPath "world") -and
    -not (Get-ChildItem -Path "mods/*.jar" -ErrorAction SilentlyContinue)) {
    throw "world/ exists but mods/ holds no jars. Starting would risk stripping the world. Set PACKWIZ_AUTO_UPDATE=true and restart to reinstall the mod set."
}

$forgeArgsFile = Resolve-ForgeArgsFile

$javaArgs = @()
$javaArgs += $javaMemoryArgs
$javaArgs += Get-JvmGcFlags $resolvedHeapMiB

# The Forge installer writes user_jvm_args.txt on every --installServer and
# keeps an existing one across a reinstall, which makes it the one place an
# operator can leave a flag and have it survive. Later flags win, so what is in
# here overrides the defaults above.
if (Test-Path -LiteralPath "user_jvm_args.txt") {
    Write-Host "Reading extra JVM flags from user_jvm_args.txt."
    $javaArgs += "@user_jvm_args.txt"
}

# The panel field, for operators with no way to edit a file. Last, so it beats
# both the defaults and user_jvm_args.txt. Splitting on one literal space would
# pass java an empty argument for every doubled space in the string.
if ($resolvedJvmExtraFlags) {
    Write-Host "Adding JVM_EXTRA_FLAGS: $resolvedJvmExtraFlags"
    $javaArgs += @($resolvedJvmExtraFlags -split '\s+' | Where-Object { $_ })
}

# nogui is a server argument rather than a JVM one, so it goes last. Without it
# the dedicated server opens its Swing console, which on this documented
# standalone Windows route means a window on every start.
if ($forgeArgsFile) {
    & java @javaArgs "@$forgeArgsFile" nogui
}
elseif (Test-Path -LiteralPath $resolvedServerJarFile) {
    & java @javaArgs -jar $resolvedServerJarFile nogui
}
else {
    # Reporting the missing jar is not the problem and sends you looking in the
    # wrong place; on a Forge install there was never meant to be one.
    throw "No Forge launch arguments and no $resolvedServerJarFile, so there is nothing to start. Re-run tools/install.ps1 to install Forge."
}
exit $LASTEXITCODE
