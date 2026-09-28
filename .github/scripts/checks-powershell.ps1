#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Set-Location (Resolve-Path (Join-Path $PSScriptRoot "../.."))

$files = @(
    "functions.ps1",
    "tools/install.ps1",
    "startup.ps1",
    "tools/update.ps1"
)
$files += Get-ChildItem -Path ".github/scripts" -Filter "*.ps1" |
    ForEach-Object { ".github/scripts/$($_.Name)" }

# Every script here declares 5.1 and runs on Windows PowerShell, but CI's Linux
# leg only has PowerShell 7, whose parser accepts syntax 5.1 does not. These
# three rules check syntax, commands and types against the 5.1 profile instead.
# They catch a 7-only parameter used by name, -AdditionalChildPath included, but
# not the same thing passed positionally: Join-Path "a" "b" "c" passes, and only
# running it on 5.1 shows the fault. Tested against 1.25.0.
$analyzerVersion = "1.25.0"
$analyzerSha256 = "14e634c828eb98efb9f40b2918ba90f139ed5eccdf663a2a747736d996995d60"
$windowsPowerShellProfile = "win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework"
$analyzerSettings = @{
    IncludeRules = @("PSUseCompatibleSyntax", "PSUseCompatibleCommands", "PSUseCompatibleTypes")
    Rules        = @{
        PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @("5.1") }
        PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @($windowsPowerShellProfile) }
        PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = @($windowsPowerShellProfile) }
    }
}

# Pinned, so the result depends on the tree and not on whichever analyzer a
# runner image carries. An installed copy is used only when it is this same
# version; otherwise the Gallery package is fetched into tmp/tools and checked
# against its SHA-256 before it is loaded.
function Import-PinnedScriptAnalyzer {
    $installed = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Where-Object { $_.Version -eq [version]$analyzerVersion } |
        Select-Object -First 1
    if ($installed) {
        Import-Module $installed.Path -Force
        return
    }

    $toolsDir = Join-Path "tmp/tools" "PSScriptAnalyzer"
    $moduleDir = Join-Path $toolsDir $analyzerVersion
    $manifest = Join-Path $moduleDir "PSScriptAnalyzer.psd1"

    if (-not (Test-Path -LiteralPath $manifest)) {
        [Console]::Error.WriteLine("Fetching PSScriptAnalyzer $analyzerVersion into tmp/tools...")
        New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
        # Expand-Archive on 5.1 refuses anything not named .zip, and a .nupkg is one.
        $package = Join-Path $toolsDir "psscriptanalyzer.$analyzerVersion.zip"
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/$analyzerVersion" `
            -OutFile $package -TimeoutSec 120 -UseBasicParsing

        if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $analyzerSha256) {
            Remove-Item -Force -ErrorAction SilentlyContinue $package
            throw "PSScriptAnalyzer $analyzerVersion did not match its pinned SHA-256."
        }

        Expand-Archive -LiteralPath $package -DestinationPath $moduleDir -Force
        Remove-Item -Force $package
    }

    Import-Module (Resolve-Path -LiteralPath $manifest).Path -Force
}

$failed = $false
$parsed = @()

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) {
        [Console]::Error.WriteLine("ERROR: $file is listed for linting but does not exist.")
        $failed = $true
        continue
    }

    $tokens = $null
    $errors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $file).Path,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        # Deliberately not Write-Error. ErrorActionPreference is Stop, so the
        # first Write-Error would terminate the run: no error detail, no exit 1,
        # and every file after this one left unchecked.
        [Console]::Error.WriteLine("ERROR: $($errors.Count) syntax error(s) in ${file}:")
        foreach ($parseError in $errors) {
            $line = $parseError.Extent.StartLineNumber
            $column = $parseError.Extent.StartColumnNumber
            [Console]::Error.WriteLine("  ${file}:${line}:${column} $($parseError.Message)")
        }
        $failed = $true
    }
    else {
        $parsed += $file
    }
}

# Only files that parsed. The analyzer's own report on a file that does not is
# noise on top of the syntax errors already printed.
if ($parsed.Count -gt 0) {
    Import-PinnedScriptAnalyzer
}

foreach ($file in $parsed) {
    $findings = @(Invoke-ScriptAnalyzer -Path $file -Settings $analyzerSettings)

    if ($findings.Count -gt 0) {
        [Console]::Error.WriteLine("ERROR: $($findings.Count) Windows PowerShell 5.1 compatibility problem(s) in ${file}:")
        foreach ($finding in $findings) {
            [Console]::Error.WriteLine("  ${file}:$($finding.Line):$($finding.Column) $($finding.Message)")
        }
        $failed = $true
    }
    else {
        Write-Host "OK $file"
    }
}

if ($failed) {
    exit 1
}
