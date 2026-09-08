#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Set-Location (Resolve-Path (Join-Path $PSScriptRoot "../.."))

$files = @(
    "tools/install.ps1",
    "startup.ps1",
    "tools/update.ps1"
)
$files += Get-ChildItem -Path ".github/scripts" -Filter "*.ps1" |
    ForEach-Object { ".github/scripts/$($_.Name)" }

$failed = $false

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
        Write-Host "OK $file"
    }
}

if ($failed) {
    exit 1
}
