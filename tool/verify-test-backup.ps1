[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BackupDirectory,
    [string]$InventoryFile = (Join-Path $PSScriptRoot '../docs/evidence/MASTER-test-preflight.json'),
    [string]$EvidenceName = 'MASTER-restore.json',
    [switch]$VerifyDemoData
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$container = 'tezrider-master-restore-20261028'
if ($EvidenceName -notmatch '^MASTER-(post-seed-)?restore\.json$') { throw 'Unexpected evidence filename.' }
$privateRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21/backups')) + [IO.Path]::DirectorySeparatorChar
$BackupDirectory = (Resolve-Path -LiteralPath $BackupDirectory).Path
if (-not ($BackupDirectory + [IO.Path]::DirectorySeparatorChar).StartsWith($privateRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only a protected local TezRider backup directory is accepted.'
}
$manifest = Get-Content -LiteralPath (Join-Path $BackupDirectory 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.project -cne 'igeisilhtmglgnqvllrx') { throw 'TEST backup required.' }
$inspection = & docker inspect --format '{{json .HostConfig.NetworkMode}} {{json .Config.Labels}}' $container
if ($LASTEXITCODE -ne 0 -or $inspection -notmatch '^"none" ' -or $inspection -notmatch '"tezrider.purpose":"isolated-restore"') {
    throw 'A separate owned restore container with network=none is required; no existing TEST or production database can be targeted.'
}
# This container was created solely for this rehearsal, has no published ports
# and cannot contact hosted services. The canonical local stack is untouched.
$schemas = @($manifest.schemas)
if ($schemas | Where-Object { $_ -notmatch '^[a-z][a-z0-9_]*$' }) { throw 'Invalid backup schema name.' }
$drop = 'drop schema if exists ' + ($schemas -join ',') + ' cascade;'
$bootstrap = $drop + ' create extension if not exists postgis with schema extensions; create extension if not exists pg_trgm with schema extensions;'
& docker exec $container psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c $bootstrap *> (Join-Path $BackupDirectory 'restore-bootstrap.private.log')
if ($LASTEXITCODE -ne 0) { throw 'Isolated schema initialization failed.' }
Add-Type -AssemblyName System.Security
$outcome = [ordered]@{
    project = $manifest.project; container = $container; network = 'none'
    existing_local_stack_modified = $false; hosted_modified = $false
    schema_restored = $false; data_restored = $false; isolated_restore_verified = $false
    status = 'FAIL'; limitation = ''; utc = [DateTime]::UtcNow.ToString('o')
}
foreach ($kind in @('schema', 'data')) {
    $entry = @($manifest.exports | Where-Object kind -eq $kind)
    if ($entry.Count -ne 1) { throw 'Missing unique backup manifest entry.' }
    $sealedPath = Join-Path $BackupDirectory ($kind + '.sql.dpapi')
    if ((Get-FileHash -LiteralPath $sealedPath -Algorithm SHA256).Hash -cne $entry[0].encrypted_sha256) { throw 'Encrypted backup hash mismatch.' }
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($sealedPath), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $entry[0].plain_sha256) { throw 'Decrypted backup hash mismatch.' }
    $sql = [Text.Encoding]::UTF8.GetString($bytes)
    $sql | & docker exec -i $container psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 --single-transaction *> (Join-Path $BackupDirectory ("restore-$kind.private.log"))
    $restoreExit = $LASTEXITCODE
    [Array]::Clear($bytes, 0, $bytes.Length)
    $sql = $null
    if ($restoreExit -ne 0) {
        $outcome.limitation = "Isolated $kind restore failed. Private diagnostic log retained; no restore acceptance claimed."
        break
    }
    $outcome[$kind + '_restored'] = $true
}
if ($outcome.schema_restored -and $outcome.data_restored) {
    # Count only; do not emit imported identity, order or document records.
    $counts = & docker exec $container psql -U supabase_admin -d postgres -At -v ON_ERROR_STOP=1 -c "select json_build_object('auth_users',(select count(*) from auth.users),'profiles',(select count(*) from public.users),'linked_profiles',(select count(*) from public.users u join auth.users a on a.id=u.auth_user_id),'storage_metadata',(select count(*) from storage.objects));"
    if ($LASTEXITCODE -eq 0) {
        $outcome.counts = $counts | ConvertFrom-Json
        $expected = Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json
        $outcome.isolated_restore_verified = $outcome.counts.auth_users -eq $expected.auth_user_count -and $outcome.counts.profiles -eq $expected.profile_count -and $outcome.counts.linked_profiles -eq $expected.linked_auth_profiles -and $outcome.counts.storage_metadata -eq $expected.storage_object_count
        if ($VerifyDemoData) {
            $demoSql = @'
select json_build_object(
 'accounts',(select count(*) from auth.users where raw_app_meta_data->>'tezrider_demo_namespace'='tezrider-owner-demo-v1'),
 'products',(select count(*) from public.products p join public.users u on u.id=p.vendor_id join auth.users a on a.id=u.auth_user_id where a.raw_app_meta_data->>'tezrider_demo_namespace'='tezrider-owner-demo-v1'),
 'addresses',(select count(*) from public.addresses d join public.users u on u.id=d.user_id join auth.users a on a.id=u.auth_user_id where a.raw_app_meta_data->>'tezrider_demo_namespace'='tezrider-owner-demo-v1'),
 'pending_riders',(select count(*) from public.users u join auth.users a on a.id=u.auth_user_id where a.raw_app_meta_data->>'tezrider_demo_namespace'='tezrider-owner-demo-v1' and u.role='rider' and u.verification_status='pending'),
 'orders',(select count(*) from public.orders o join public.users u on u.id=o.user_id join auth.users a on a.id=u.auth_user_id where a.raw_app_meta_data->>'tezrider_demo_namespace'='tezrider-owner-demo-v1'));
'@
            $demo = & docker exec $container psql -U supabase_admin -d postgres -At -v ON_ERROR_STOP=1 -c $demoSql
            if ($LASTEXITCODE -ne 0) { $outcome.isolated_restore_verified = $false }
            else {
                $outcome.demo = $demo | ConvertFrom-Json
                $outcome.isolated_restore_verified = $outcome.isolated_restore_verified -and $outcome.demo.accounts -eq 7 -and $outcome.demo.products -eq 12 -and $outcome.demo.addresses -eq 2 -and $outcome.demo.pending_riders -eq 2 -and $outcome.demo.orders -eq 0
            }
        }
        if ($outcome.isolated_restore_verified) { $outcome.status = 'BOUNDED PASS' }
    }
    $outcome.limitation = 'Schema/data and association counts only; application runtime, Storage bytes, external secrets/configuration and cross-machine DPAPI recovery are separate gates.'
}
$outcome | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repo ('docs/evidence/' + $EvidenceName)) -Encoding utf8
$outcome | ConvertTo-Json -Depth 8
if (-not $outcome.isolated_restore_verified) { exit 1 }
