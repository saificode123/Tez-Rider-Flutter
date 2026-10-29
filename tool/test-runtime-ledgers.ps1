[CmdletBinding()]
param(
    [ValidateSet('Backup','Restore')][string]$Mode = 'Backup',
    [Parameter(Mandatory)][string]$BackupDirectory,
    [string]$CliPath
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$boundary = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21/backups')) + [IO.Path]::DirectorySeparatorChar
$BackupDirectory = (Resolve-Path -LiteralPath $BackupDirectory).Path
if (-not ($BackupDirectory + [IO.Path]::DirectorySeparatorChar).StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Protected TEST backup directory required.' }
$manifest = Get-Content (Join-Path $BackupDirectory 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.project -cne 'igeisilhtmglgnqvllrx') { throw 'TEST backup required.' }
Add-Type -AssemblyName System.Security
$encrypted = Join-Path $BackupDirectory 'runtime-ledgers.dpapi'
$metadata = Join-Path $BackupDirectory 'runtime-ledgers-manifest.json'
if ($Mode -eq 'Backup') {
    if (-not $CliPath) { $CliPath = Join-Path $repo '.fr21-local/tools/supabase.exe' }
    $CliPath = (Resolve-Path -LiteralPath $CliPath).Path
    if (Test-Path $encrypted) { throw 'Runtime ledger export exists; do not silently replace a captured checkpoint.' }
    if ((Get-Content (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne $manifest.project) { throw 'TEST target required.' }
    $rawFile = Join-Path $BackupDirectory 'runtime-ledgers.private.json'
    Push-Location $repo
    try {
        & $CliPath db query --linked --project-ref igeisilhtmglgnqvllrx --file (Join-Path $repo 'supabase/inspection/RELEASE-recovery-ledgers.sql') --output json *> $rawFile
        $queryExit = $LASTEXITCODE
    } finally { Pop-Location }
    if ($queryExit -ne 0) { throw 'Read-only TEST migration-ledger export failed.' }
    $raw = Get-Content $rawFile -Raw
    $ledgers = ($raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json).rows[0].ledgers
    if (@($ledgers.auth).Count -lt 1 -or @($ledgers.storage).Count -lt 1) { throw 'Missing runtime migration history.' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($ledgers | ConvertTo-Json -Depth 12 -Compress))
    [IO.File]::WriteAllBytes($encrypted,[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
    $verified = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($encrypted),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $plainHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($plainHash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($verified))) { throw 'Runtime ledger encryption roundtrip failed.' }
    $summary = @{
        project = $manifest.project; captured_utc = [DateTime]::UtcNow.ToString('o')
        auth_versions = @($ledgers.auth).Count; storage_versions = @($ledgers.storage).Count
        latest_auth = @($ledgers.auth)[-1].version; latest_storage = @($ledgers.storage)[-1].name
        encrypted_sha256 = (Get-FileHash $encrypted -Algorithm SHA256).Hash
        plaintext_sha256 = $plainHash; encrypted_roundtrip = $true
        scope = 'Service-owned migration ledgers exported explicitly because CLI logical data dump omits them. Separate capture timestamp; no new data/schema export or point-in-time snapshot consistency implied.'
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content $metadata -Encoding utf8
    $summary | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $repo 'docs/evidence/RELEASE-backup-ledgers.json') -Encoding utf8
    Remove-Item -LiteralPath $rawFile
    [Array]::Clear($bytes,0,$bytes.Length); [Array]::Clear($verified,0,$verified.Length)
    $summary | ConvertTo-Json -Depth 6
    return
}
$container = 'tezrider-master-restore-20261028'
$inspection = & docker inspect --format '{{json .HostConfig.NetworkMode}} {{json .Config.Labels}}' $container
if ($LASTEXITCODE -ne 0 -or $inspection -notmatch '^"none" ' -or $inspection -notmatch '"tezrider.purpose":"isolated-restore"') { throw 'Owned offline restore container required.' }
$expected = Get-Content $metadata -Raw | ConvertFrom-Json
if ($expected.project -cne $manifest.project -or (Get-FileHash $encrypted -Algorithm SHA256).Hash -cne $expected.encrypted_sha256) { throw 'Runtime ledger backup integrity mismatch.' }
$bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($encrypted),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
try {
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $expected.plaintext_sha256) { throw 'Runtime ledger plaintext hash mismatch.' }
    $encoded = [Convert]::ToBase64String($bytes)
    # Only service migration metadata is replaced in the owned offline clone.
    # No Auth identity, profile, object, order, audit or hosted row is altered.
    $sql = @'
begin;
delete from auth.schema_migrations;
insert into auth.schema_migrations select * from jsonb_populate_recordset(null::auth.schema_migrations,
 (convert_from(decode('__LEDGERS__','base64'),'UTF8')::jsonb)->'auth');
delete from storage.migrations;
insert into storage.migrations select * from jsonb_populate_recordset(null::storage.migrations,
 (convert_from(decode('__LEDGERS__','base64'),'UTF8')::jsonb)->'storage');
select json_build_object('auth_versions',(select count(*) from auth.schema_migrations),
 'storage_versions',(select count(*) from storage.migrations));
commit;
'@
    $sql = $sql.Replace('__LEDGERS__',$encoded)
    $privateLog = Join-Path $BackupDirectory 'release-runtime-ledger-restore.private.log'
    $sql | & docker exec -i $container psql -qAt -U supabase_admin -d postgres -v ON_ERROR_STOP=1 *> $privateLog
    if ($LASTEXITCODE -ne 0) { throw 'Offline runtime ledger restore failed; private diagnostic retained.' }
    $counts = Get-Content $privateLog | Where-Object { $_.StartsWith('{') } | ConvertFrom-Json
    if ($counts.auth_versions -ne $expected.auth_versions -or $counts.storage_versions -ne $expected.storage_versions) { throw 'Offline runtime ledger counts differ.' }
    @{project=$manifest.project;utc=[DateTime]::UtcNow.ToString('o');counts=$counts;hosted_modified=$false;status='BOUNDED PASS'} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $repo 'docs/evidence/RELEASE-runtime-ledgers.json') -Encoding utf8
    'Offline Auth/Storage migration ledgers restored and count-verified.'
} finally { [Array]::Clear($bytes,0,$bytes.Length); $sql=$null; $encoded=$null }
