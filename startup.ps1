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
    [int]$VoicePort = 24454,
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

$resolvedMemoryMiB = Resolve-NonNegativeMiB "--memory" $MemoryMiB $env:SERVER_MEMORY
$resolvedJvmMemoryMiB = Resolve-NonNegativeMiB "--jvm-memory" $JvmMemoryMiB $env:JVM_MEMORY
$javaMemoryArgs = Get-JavaMemoryArgs $resolvedMemoryMiB $resolvedJvmMemoryMiB

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
    & java @javaMemoryArgs "@win_args.txt"
}
else {
    & java @javaMemoryArgs -jar $ServerJarFile
}
exit $LASTEXITCODE
