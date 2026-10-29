[CmdletBinding()]
param(
    [string]$CliPath = (Join-Path $PSScriptRoot '../.fr21-local/tools/supabase.exe'),
    [string]$PrivateRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21/backups'),
    [switch]$PreflightOnly,
    [string]$EvidenceName = 'MASTER-backup.json'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$targetRef = 'igeisilhtmglgnqvllrx'
if ($EvidenceName -notmatch '^MASTER-(post-seed-)?backup\.json$') { throw 'Unexpected evidence filename.' }
if ((Get-Content -LiteralPath (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne $targetRef) {
    throw 'Authorized TEST link required; production backup is not part of this helper.'
}
$CliPath = (Resolve-Path -LiteralPath $CliPath).Path
$dockerVersion = & docker info --format '{{.ServerVersion}}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $dockerVersion) { throw 'Docker backend unavailable; no remote export was started.' }
# Windows user-bound encryption; no key/password enters the command or Git.
Add-Type -AssemblyName System.Security
$schemaNames = @('public', 'auth', 'storage', 'supabase_migrations',
    'checklist_private', 'final1_private', 'final2_private', 'final_delivery_private',
    'fr04_private', 'fr10_private', 'fr13_private', 'fr14_private',
    'fr17_private', 'fr25_private', 'fr30_private', 'fr32_private')
$inspection = Get-Content -LiteralPath (Join-Path $repo 'docs/evidence/MASTER-test-preflight.json') -Raw | ConvertFrom-Json
if (Compare-Object ($schemaNames | Sort-Object) ($inspection.application_schemas | Sort-Object)) {
    throw 'Backup schema list differs from inspected TEST schemas; review it before export.'
}
$probe = [Text.Encoding]::UTF8.GetBytes('TezRider TEST backup encryption preflight')
$probeSealed = [Security.Cryptography.ProtectedData]::Protect($probe, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
$probeRestored = [Security.Cryptography.ProtectedData]::Unprotect($probeSealed, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
if ([Convert]::ToHexString($probe) -cne [Convert]::ToHexString($probeRestored)) {
    throw 'Windows user-bound backup encryption unavailable.'
}
if ($PreflightOnly) {
    Write-Output 'TEST target, CLI, Docker, all 16 inspected schemas and DPAPI round-trip preflight passed. No export or database change.'
    return
}
$privateDirectory = Join-Path $PrivateRoot ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $privateDirectory -Force | Out-Null
$privateDirectory = (Resolve-Path -LiteralPath $privateDirectory).Path
$results = @()
foreach ($kind in @('schema', 'data', 'roles')) {
    if ((Get-Content -LiteralPath (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne $targetRef) {
        throw 'TEST link changed; export stopped.'
    }
    $plain = Join-Path $privateDirectory ($kind + '.sql')
    $encrypted = $plain + '.dpapi'
    $log = Join-Path $privateDirectory ($kind + '.private.log')
    $arguments = @('db', 'dump', '--linked', '--project-ref', $targetRef, '--file', $plain)
    if ($kind -eq 'roles') { $arguments += '--role-only' }
    else { $arguments += @('--schema', ($schemaNames -join ',')) }
    if ($kind -eq 'data') { $arguments += @('--data-only', '--use-copy') }
    Push-Location -LiteralPath $repo
    try { & $CliPath @arguments *> $log; $dumpExit = $LASTEXITCODE }
    finally { Pop-Location }
    if ($dumpExit -ne 0) { throw "TEST $kind export failed; private diagnostic log retained. No verified backup claimed." }
    $bytes = [IO.File]::ReadAllBytes($plain)
    if ($bytes.Length -lt 100) { throw "TEST $kind export unexpectedly empty." }
    $sealed = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($encrypted, $sealed)
    $restored = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($encrypted), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $plainHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($plainHash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($restored))) {
        throw "TEST $kind encrypted backup round-trip failed; plaintext retained for recovery."
    }
    # Only a known, single file inside this newly created backup directory.
    if ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $plain).Path) -cne $privateDirectory) {
        throw 'Backup plaintext path boundary mismatch.'
    }
    Remove-Item -LiteralPath $plain
    $results += [pscustomobject]@{
        kind = $kind; plain_bytes = $bytes.Length; plain_sha256 = $plainHash
        encrypted_sha256 = (Get-FileHash -LiteralPath $encrypted -Algorithm SHA256).Hash
        encrypted_round_trip = $true
    }
    [Array]::Clear($bytes, 0, $bytes.Length)
    [Array]::Clear($restored, 0, $restored.Length)
}
$manifest = [pscustomobject]@{
    project = $targetRef; created_utc = (Get-Date).ToUniversalTime().ToString('o')
    encryption = 'Windows DPAPI CurrentUser; original Windows user/profile required for recovery'
    exports = $results; schemas = $schemaNames
    storage_object_bytes_backed_up = $false; isolated_restore_verified = $false
    scope = 'Database exports only. Storage object metadata is not object bytes. External secrets/configuration and cross-machine recovery require separate protected handover.'
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $privateDirectory 'manifest.json') -Encoding utf8
& (Join-Path $PSScriptRoot 'test-runtime-ledgers.ps1') -Mode Backup -BackupDirectory $privateDirectory -CliPath $CliPath
$manifest | Add-Member -NotePropertyName runtime_ledgers_included -NotePropertyValue $true
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $privateDirectory 'manifest.json') -Encoding utf8
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repo ('docs/evidence/' + $EvidenceName)) -Encoding utf8
Write-Output "TEST database exports encrypted and round-trip checked. Private backup directory: $privateDirectory"
Write-Output 'This database-export helper alone does not verify Storage bytes, external configuration or isolated restore; consult their separate evidence.'
