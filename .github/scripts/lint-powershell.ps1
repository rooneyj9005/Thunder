#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Set-Location (Resolve-Path (Join-Path $PSScriptRoot "../.."))

$files = @(
    "install.ps1",
    "startup.ps1",
    "update.ps1"
)

$failed = $false

foreach ($file in $files) {
    $tokens = $null
    $errors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $file),
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        Write-Error "PowerShell syntax errors in $file"
        $errors | ForEach-Object {
            Write-Error $_.Message
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
