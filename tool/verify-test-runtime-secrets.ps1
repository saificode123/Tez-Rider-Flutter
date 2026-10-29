[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$container = 'tezrider-master-restore-20261028'
$boundary = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21/backups')) + [IO.Path]::DirectorySeparatorChar
$BackupDirectory = (Resolve-Path -LiteralPath $BackupDirectory).Path
if (-not ($BackupDirectory + [IO.Path]::DirectorySeparatorChar).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Protected TEST backup required.' }
$manifest = Get-Content (Join-Path $BackupDirectory 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.project -cne 'igeisilhtmglgnqvllrx') { throw 'TEST snapshot required.' }
$inspection = & docker inspect --format '{{json .HostConfig.NetworkMode}} {{json .Config.Labels}}' $container
if ($LASTEXITCODE -ne 0 -or $inspection -notmatch '^"none" ' -or $inspection -notmatch '"tezrider.purpose":"isolated-restore"') { throw 'Owned offline recovery container required.' }
$restored = Get-Content (Join-Path $repo 'docs/evidence/RELEASE-runtime-restore.json') -Raw | ConvertFrom-Json
if (-not $restored.isolated_restore_verified -or $restored.container -cne $container) { throw 'Verified isolated restore required.' }
$expected = Get-Content (Join-Path $repo 'docs/evidence/MASTER-secret-backup.json') -Raw | ConvertFrom-Json
$entry = @($expected.encrypted_files | Where-Object name -eq 'vault-export')
$sealed = Join-Path $BackupDirectory 'vault-export.dpapi'
if ($entry.Count -ne 1 -or (Get-FileHash $sealed -Algorithm SHA256).Hash -cne $entry[0].encrypted_sha256) { throw 'Protected Vault export hash mismatch.' }
Add-Type -AssemblyName System.Security
$bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($sealed), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $secrets = @(($text.Substring($text.IndexOf('{')) | ConvertFrom-Json).rows[0].secrets)
    if ($secrets.Count -ne $expected.vault_secret_count -or $secrets.Count -eq 0) { throw 'Vault inventory mismatch.' }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($secrets | ConvertTo-Json -Depth 8 -Compress)))
    # Base64 is SQL-safe here; values travel only on stdin to the offline
    # container. Never echo SQL, secret names, decrypted CNICs or raw errors.
    $sql = @'
begin;
do $recovery$
declare item jsonb;
begin
 if (select count(*) from vault.secrets) <> 0 then raise exception 'Fresh isolated Vault required'; end if;
 for item in select * from jsonb_array_elements(convert_from(decode('__VAULT_BASE64__','base64'),'UTF8')::jsonb) loop
  perform vault.create_secret(item->>'secret',item->>'name',item->>'description');
 end loop;
end $recovery$;
select json_build_object('vault_entries',(select count(*) from vault.decrypted_secrets),
 'ciphertexts',count(*),'decrypted_cnic_format_valid',count(*) filter(where fr04_private.decrypt_cnic(cnic) ~ '^[0-9]{13}$'),
 'masked_cnic_format_valid',count(*) filter(where fr04_private.mask_cnic(cnic) ~ '^[0-9][*]{3}[0-9]-[*]{7}-[*]$'))
from public.users where cnic like 'pgp:v1:%';
commit;
'@
    $sql = $sql.Replace('__VAULT_BASE64__', $encoded)
    $privateLog = Join-Path $BackupDirectory 'release-runtime-secrets.private.log'
    $sql | & docker exec -i $container psql -qAt -U supabase_admin -d postgres -v ON_ERROR_STOP=1 --single-transaction *> $privateLog
    if ($LASTEXITCODE -ne 0) { throw 'Offline runtime decryption failed; private diagnostic retained.' }
    $counts = Get-Content $privateLog | Where-Object { $_.StartsWith('{') } | ConvertFrom-Json
    if ($counts.vault_entries -ne $secrets.Count -or $counts.ciphertexts -lt 1 -or $counts.decrypted_cnic_format_valid -ne $counts.ciphertexts -or $counts.masked_cnic_format_valid -ne $counts.ciphertexts) { throw 'Restored runtime decryption acceptance failed.' }
    $result = @{
        project = $manifest.project; utc = [DateTime]::UtcNow.ToString('o'); network = 'none'
        container = $container; counts = $counts; elapsed_seconds = [Math]::Round($timer.Elapsed.TotalSeconds,3)
        hosted_modified = $false; status = 'BOUNDED PASS'
        limitation = 'Actual backed-up CNIC ciphertexts decrypted and masked using recovered Vault values in the isolated database. New Vault IDs are not a reference-mapping restoration; Auth/Edge configuration, Storage runtime upload and cross-machine recovery remain separate.'
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $repo 'docs/evidence/RELEASE-runtime-secrets.json') -Encoding utf8
    $result | ConvertTo-Json -Depth 6
} finally {
    [Array]::Clear($bytes,0,$bytes.Length)
    $sql = $null; $text = $null; $secrets = $null; $encoded = $null
}
