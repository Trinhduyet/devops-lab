[CmdletBinding()]
param(
    [uri]$BaseUri = 'http://127.0.0.1:8080',
    [string]$ExpectedService = 'devops-lab-sample-api'
)

$ErrorActionPreference = 'Stop'
$base = $BaseUri.AbsoluteUri.TrimEnd('/')

$root = Invoke-RestMethod -Method Get -Uri "$base/" -TimeoutSec 5
if ($root.service -ne $ExpectedService -or $root.status -ne 'ok' -or [string]::IsNullOrWhiteSpace($root.version)) {
    throw 'GET / returned an unexpected service payload.'
}
Write-Output 'PASS: GET / returned the configured service and version.'

$live = Invoke-RestMethod -Method Get -Uri "$base/health/live" -TimeoutSec 5
if ($live.status -ne 'live') { throw 'GET /health/live returned an unexpected payload.' }
Write-Output 'PASS: GET /health/live returned live.'

$ready = Invoke-RestMethod -Method Get -Uri "$base/health/ready" -TimeoutSec 5
if ($ready.status -ne 'ready') { throw 'GET /health/ready returned an unexpected payload.' }
Write-Output 'PASS: GET /health/ready returned ready.'
