$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$files = @(
    Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.ps1'
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'applications/dotnet-sample-api/tests') -Recurse -File -Filter '*.ps1'
) | Sort-Object FullName
if ($files.Count -eq 0) { throw 'No PowerShell scripts were found for syntax validation.' }

$failed = 0
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            Write-Error "FAIL: $($file.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)" -ErrorAction Continue
        }
        $failed++
    } else {
        Write-Output "PASS: PowerShell syntax $([IO.Path]::GetRelativePath($repoRoot, $file.FullName))"
    }
}

if ($failed -gt 0) { exit 1 }
