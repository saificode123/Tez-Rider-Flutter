[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$reference='igeisilhtmglgnqvllrx'
$private=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21'
$boundary=[IO.Path]::GetFullPath((Join-Path $private 'backups'))+[IO.Path]::DirectorySeparatorChar
$BackupDirectory=(Resolve-Path -LiteralPath $BackupDirectory).Path
if (-not ($BackupDirectory+[IO.Path]::DirectorySeparatorChar).StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Protected backup directory required.' }
if ((Get-Content -LiteralPath (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne $reference) { throw 'Authorized TEST link required.' }
$manifest=Get-Content -LiteralPath (Join-Path $BackupDirectory 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.project -cne $reference) { throw 'TEST export required.' }
Add-Type -AssemblyName System.Security
function Seal-File([string]$Source,[string]$Name) {
    $bytes=[IO.File]::ReadAllBytes($Source)
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $sealed=[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $target=Join-Path $BackupDirectory ($Name+'.dpapi')
    [IO.File]::WriteAllBytes($target,$sealed)
    $recovered=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($target),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    if ($hash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($recovered))) { throw 'Protected configuration recovery hash mismatch.' }
    $result=@{name=$Name; bytes=$bytes.Length; encrypted_sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash; decrypted_hash_matches=$true}
    [Array]::Clear($bytes,0,$bytes.Length); [Array]::Clear($recovered,0,$recovered.Length)
    return $result
}
$raw=Join-Path $BackupDirectory 'vault-export.private.json'
$cli=Join-Path $repo '.fr21-local/tools/supabase.exe'
Push-Location -LiteralPath $repo
try { & $cli db query --linked --project-ref $reference --file (Join-Path $repo 'supabase/inspection/MASTER-vault-backup.sql') --output json *> $raw; $queryExit=$LASTEXITCODE }
finally { Pop-Location }
if ($queryExit -ne 0) { throw 'TEST Vault export failed; private diagnostic file retained, no secret values emitted.' }
$text=Get-Content -LiteralPath $raw -Raw
$secretRows=(($text.Substring($text.IndexOf('{')) | ConvertFrom-Json).rows[0]).secrets
$count=@($secretRows).Count
$records=@(Seal-File $raw 'vault-export')
if ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $raw).Path) -cne $BackupDirectory) { throw 'Private plaintext cleanup boundary mismatch.' }
Remove-Item -LiteralPath $raw
$text=$null; $secretRows=$null
$localEnvironment=Join-Path $repo 'supabase/functions/.env.test.local'
if (Test-Path -LiteralPath $localEnvironment) { $records+=Seal-File $localEnvironment 'local-test-function-environment' }
$demoCredentials=Join-Path $private 'master-demo-credentials.dpapi'
if (Test-Path -LiteralPath $demoCredentials) { $records+=Seal-File $demoCredentials 'encrypted-demo-credential-file' }
$summary=@{
    project=$reference; utc=[DateTime]::UtcNow.ToString('o'); vault_secret_count=$count
    encrypted_files=$records; plaintext_vault_export_removed=$true
    limits='Vault values and existing local TEST function environment encrypted with Windows DPAPI. No values/names printed. Remote Edge/Auth configuration parity, restoring Vault references, document decryption and cross-machine recovery remain unverified.'
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repo 'docs/evidence/MASTER-secret-backup.json') -Encoding utf8
Write-Output "Protected TEST configuration backed up and decryption hashes verified. Vault entries: $count. No secret values emitted."
