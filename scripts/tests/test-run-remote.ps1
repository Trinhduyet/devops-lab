$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$helper = Join-Path $repoRoot 'scripts/run-remote.ps1'
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("devops-run-remote-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

$sshMock = Join-Path $tempRoot 'ssh-mock.ps1'
$scpMock = Join-Path $tempRoot 'scp-mock.ps1'
$sshMockContent = @'
if ($null -eq $global:MockSshCallCount) { $global:MockSshCallCount = 0 }
$global:MockSshCallCount++
$remoteCommand = [string]$args[-1]
Add-Content -LiteralPath $env:MOCK_LOG_PATH -Value ("SSH|{0}|{1}" -f $global:MockSshCallCount, $remoteCommand)
if ($env:MOCK_SSH_FAIL_AT -and $global:MockSshCallCount -eq [int]$env:MOCK_SSH_FAIL_AT) { $global:LASTEXITCODE = 255; return }
if ($global:MockSshCallCount -eq 1) { Write-Output '/tmp/devops-lab.ABCDE123'; $global:LASTEXITCODE = 0; return }
if ($remoteCommand -like 'bash -n *' -and $env:MOCK_BASH_N_EXIT) { $global:LASTEXITCODE = [int]$env:MOCK_BASH_N_EXIT; return }
if ($remoteCommand -match "^bash\s+'[^']+/validate\.sh'\s+'lab-(03|07)'$") { $global:LASTEXITCODE = [int]$env:MOCK_REMOTE_EXIT; return }
if ($remoteCommand -match "^HOST_CHANGE_SSH_KEY_VERIFIED=PASS HOST_CHANGE_EVIDENCE_FILE='[^']+' bash '[^']+/validate\.sh' 'host-change'$" -or $remoteCommand -match "^PUBLIC_SERVICES_SSH_KEY_VERIFIED=PASS PUBLIC_SERVICES_EVIDENCE_FILE='[^']+' bash '[^']+/validate\.sh' 'public-services'$") { $global:LASTEXITCODE = [int]$env:MOCK_REMOTE_EXIT; return }
if ($remoteCommand -like '*rm -f*' -and $env:MOCK_CLEANUP_FAIL -eq '1') { $global:LASTEXITCODE = 24; return }
$global:LASTEXITCODE = 0
'@
$scpMockContent = @'
Add-Content -LiteralPath $env:MOCK_LOG_PATH -Value ("SCP|{0}" -f ($args -join ' '))
if ($env:MOCK_SCP_EXIT) { $global:LASTEXITCODE = [int]$env:MOCK_SCP_EXIT } else { $global:LASTEXITCODE = 0 }
'@
Set-Content -LiteralPath $sshMock -Value $sshMockContent -Encoding utf8
Set-Content -LiteralPath $scpMock -Value $scpMockContent -Encoding utf8

function Invoke-MockScenario {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$ExpectedExit,
        [string]$Phase = 'lab-03',
        [hashtable]$Environment = @{},
        [string]$ExpectedLog = '',
        [string]$ForbiddenLog = ''
    )

    $logPath = Join-Path $tempRoot "$Name.log"
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    $env:MOCK_LOG_PATH = $logPath
    foreach ($variable in 'MOCK_SSH_FAIL_AT', 'MOCK_SCP_EXIT', 'MOCK_REMOTE_EXIT', 'MOCK_CLEANUP_FAIL', 'MOCK_BASH_N_EXIT') {
        Remove-Item -Path "Env:$variable" -ErrorAction SilentlyContinue
    }
    foreach ($entry in $Environment.GetEnumerator()) { Set-Item -Path "Env:$($entry.Key)" -Value ([string]$entry.Value) }

    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $childOutput = & $pwsh -NoLogo -NoProfile -File $helper -Phase $Phase -SshCommand $sshMock -ScpCommand $scpMock 2>&1
    $actualExit = $LASTEXITCODE
    if ($actualExit -ne $ExpectedExit) { throw "$Name expected exit $ExpectedExit, got $actualExit. Output: $($childOutput -join ' ')" }

    $log = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { '' }
    if ($ExpectedLog -and $log -notlike "*$ExpectedLog*") { throw "$Name did not log expected call marker '$ExpectedLog'. Actual calls: $log" }
    if ($ForbiddenLog -and $log -like "*$ForbiddenLog*") { throw "$Name unexpectedly logged forbidden call marker '$ForbiddenLog'." }
    Write-Output "PASS: remote helper mock scenario $Name (exit=$actualExit)."
}

try {
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'run-remote.ps1 is missing.' }
    Invoke-MockScenario -Name success -ExpectedExit 0 -Environment @{ MOCK_REMOTE_EXIT = 0 } -ExpectedLog 'rm -f'
    Invoke-MockScenario -Name host-change-context -Phase host-change -ExpectedExit 0 -Environment @{ MOCK_REMOTE_EXIT = 0 } -ExpectedLog 'HOST_CHANGE_SSH_KEY_VERIFIED=PASS'
    Invoke-MockScenario -Name lab07-context -Phase lab-07 -ExpectedExit 0 -Environment @{ MOCK_REMOTE_EXIT = 0 } -ExpectedLog 'lab07-docker-smoke.sh'
    Invoke-MockScenario -Name ssh-create-failure -ExpectedExit 1 -Environment @{ MOCK_SSH_FAIL_AT = 1 } -ExpectedLog 'SSH|1|' -ForbiddenLog 'rm -f'
    Invoke-MockScenario -Name ssh-mkdir-failure -ExpectedExit 1 -Environment @{ MOCK_SSH_FAIL_AT = 2 } -ExpectedLog 'rm -f'
    Invoke-MockScenario -Name remote-bash-syntax-failure -ExpectedExit 1 -Environment @{ MOCK_BASH_N_EXIT = 2 } -ExpectedLog 'rm -f'
    Invoke-MockScenario -Name scp-failure -ExpectedExit 1 -Environment @{ MOCK_SCP_EXIT = 23 } -ExpectedLog 'rm -f'
    Invoke-MockScenario -Name remote-exit-2 -ExpectedExit 2 -Environment @{ MOCK_REMOTE_EXIT = 2 } -ExpectedLog 'rm -f'
    Invoke-MockScenario -Name cleanup-failure -ExpectedExit 1 -Environment @{ MOCK_REMOTE_EXIT = 0; MOCK_CLEANUP_FAIL = 1 } -ExpectedLog 'rm -f'
} finally {
    foreach ($variable in 'MOCK_LOG_PATH', 'MOCK_SSH_FAIL_AT', 'MOCK_SCP_EXIT', 'MOCK_REMOTE_EXIT', 'MOCK_CLEANUP_FAIL', 'MOCK_BASH_N_EXIT') {
        Remove-Item -Path "Env:$variable" -ErrorAction SilentlyContinue
    }
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and $resolvedTemp -match '^.*[\\/]devops-run-remote-test-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    } else {
        throw 'Refused to remove an unexpected mock test directory.'
    }
    $global:LASTEXITCODE = 0
}
