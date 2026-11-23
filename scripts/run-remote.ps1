[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('phase-0', 'lab-01', 'lab-02', 'lab-03', 'lab-04', 'lab-05', 'lab-06', 'host-change', 'public-services')]
    [string]$Phase,
    [string]$SshAlias = 'devops-lab',
    [string]$SshCommand = 'ssh.exe',
    [string]$ScpCommand = 'scp.exe'
)

$ErrorActionPreference = 'Stop'
$ssh = Get-Command $SshCommand -ErrorAction Stop
$scp = Get-Command $ScpCommand -ErrorAction Stop
$repoRoot = Split-Path -Parent $PSScriptRoot
$sshOptions = @('-o', 'BatchMode=yes', '-o', 'PreferredAuthentications=publickey', '-o', 'PasswordAuthentication=no', '-o', 'KbdInteractiveAuthentication=no')
$scriptNames = switch ($Phase) {
    'phase-0' { @('preflight.sh', 'security-baseline.sh', 'validate.sh') }
    'lab-01' { @('lab01-readonly.sh', 'validate.sh') }
    'lab-02' { @('lab02-systemd.sh', 'validate.sh') }
    'lab-03' { @('lab03-performance.sh', 'validate.sh') }
    'lab-04' { @('lab04-networking.sh', 'validate.sh') }
    'lab-05' { @('lab05-storage.sh', 'validate.sh') }
    'lab-06' { @('lab06-bash-automation.sh', 'validate.sh') }
    'host-change' { @('validate.sh') }
    'public-services' { @('validate.sh') }
}

foreach ($name in $scriptNames) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw "Required script is missing or empty: $path" }
}

$evidencePath = Join-Path $repoRoot 'docs/evidence/public-services.env'
$uploadEvidence = $Phase -in @('host-change', 'public-services') -and (Test-Path -LiteralPath $evidencePath -PathType Leaf)
if ($uploadEvidence -and (Get-Item -LiteralPath $evidencePath).Length -eq 0) { throw 'Manual provider/recovery evidence file is empty.' }

$tempOutput = & $ssh.Source @sshOptions $SshAlias 'umask 077; mktemp -d /tmp/devops-lab.XXXXXXXX'
if ($LASTEXITCODE -ne 0) { throw "Could not create a remote temporary directory (ssh exit=$LASTEXITCODE)." }
$remoteDir = ($tempOutput | Out-String).Trim()
if ($remoteDir -notmatch '^/tmp/devops-lab\.[A-Za-z0-9]{8}$') { throw 'Remote mktemp returned an unexpected path; cleanup was not attempted.' }

$remoteScripts = "$remoteDir/scripts"
$remoteExit = 0
try {
    & $ssh.Source @sshOptions $SshAlias "mkdir -m 700 -- '$remoteScripts'"
    if ($LASTEXITCODE -ne 0) { throw "Could not prepare the private temporary script directory (ssh exit=$LASTEXITCODE)." }

    $localPaths = @($scriptNames | ForEach-Object { Join-Path $PSScriptRoot $_ })
    $destination = '{0}:{1}/' -f $SshAlias, $remoteScripts
    & $scp.Source @sshOptions @localPaths $destination
    if ($LASTEXITCODE -ne 0) { throw "Could not upload the lab scripts (scp exit=$LASTEXITCODE)." }
    if ($uploadEvidence) {
        $evidenceDestination = '{0}:{1}/evidence.env' -f $SshAlias, $remoteScripts
        & $scp.Source @sshOptions $evidencePath $evidenceDestination
        if ($LASTEXITCODE -ne 0) { throw "Could not upload manual evidence to the private temporary path (scp exit=$LASTEXITCODE)." }
    }

    & $ssh.Source @sshOptions $SshAlias "chmod 700 -- '$remoteScripts'/*.sh"
    if ($LASTEXITCODE -ne 0) { throw "Could not set private executable permissions in the temporary directory (ssh exit=$LASTEXITCODE)." }

    foreach ($name in $scriptNames) {
        $remoteFile = "$remoteScripts/$name"
        & $ssh.Source @sshOptions $SshAlias "bash -n '$remoteFile'"
        if ($LASTEXITCODE -ne 0) { throw "Remote bash -n failed for $name (exit=$LASTEXITCODE)." }
        Write-Host "PASS: bash -n $name"
    }

    if ($Phase -eq 'public-services') {
        & $ssh.Source @sshOptions $SshAlias "PUBLIC_SERVICES_SSH_KEY_VERIFIED=PASS PUBLIC_SERVICES_EVIDENCE_FILE='$remoteScripts/evidence.env' bash '$remoteScripts/validate.sh' '$Phase'"
    } elseif ($Phase -eq 'host-change') {
        & $ssh.Source @sshOptions $SshAlias "HOST_CHANGE_SSH_KEY_VERIFIED=PASS HOST_CHANGE_EVIDENCE_FILE='$remoteScripts/evidence.env' bash '$remoteScripts/validate.sh' '$Phase'"
    } else {
        & $ssh.Source @sshOptions $SshAlias "bash '$remoteScripts/validate.sh' '$Phase'"
    }
    $remoteExit = $LASTEXITCODE
}
finally {
    $cleanup = "if [[ '$remoteDir' =~ ^/tmp/devops-lab\.[A-Za-z0-9]{8}$ ]]; then if [[ -d '$remoteScripts' ]]; then rm -f -- '$remoteScripts'/*.sh '$remoteScripts/evidence.env' && rmdir -- '$remoteScripts' || exit; fi; rmdir -- '$remoteDir'; else exit 64; fi"
    & $ssh.Source @sshOptions $SshAlias $cleanup
    if ($LASTEXITCODE -ne 0) { throw "Remote temporary-directory cleanup failed (ssh exit=$LASTEXITCODE); inspect only $remoteDir." }
    Write-Host 'PASS: remote temporary scripts and directory removed.'
}

if ($remoteExit -ne 0) { exit $remoteExit }
