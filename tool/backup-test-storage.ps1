[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$reference = 'igeisilhtmglgnqvllrx'
$private = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21'
$boundary = [IO.Path]::GetFullPath((Join-Path $private 'backups')) + [IO.Path]::DirectorySeparatorChar
$BackupDirectory = (Resolve-Path -LiteralPath $BackupDirectory).Path
if (-not ($BackupDirectory + [IO.Path]::DirectorySeparatorChar).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Protected backup directory required.' }
$manifest = Get-Content -LiteralPath (Join-Path $BackupDirectory 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.project -cne $reference) { throw 'TEST database backup required.' }
$cli = Join-Path $repo '.fr21-local/tools/supabase.exe'
function Read-ObjectInventory([string]$Name) {
    if ((Get-Content -LiteralPath (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne $reference) { throw 'TEST target changed.' }
    $file = Join-Path $BackupDirectory $Name
    Push-Location -LiteralPath $repo
    try { & $cli db query --linked --project-ref $reference --file (Join-Path $repo 'supabase/inspection/MASTER-storage-inventory.sql') --output json *> $file; $queryExit = $LASTEXITCODE }
    finally { Pop-Location }
    if ($queryExit -ne 0) { throw 'TEST Storage inventory failed; private log retained.' }
    $raw = Get-Content -LiteralPath $file -Raw
    return @((($raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json).rows[0]).objects)
}
$before = @(Read-ObjectInventory 'storage-before.private.json')
$knownBytes = ($before | ForEach-Object { if ($_.size) { [long]$_.size } else { 0 } } | Measure-Object -Sum).Sum
if ($knownBytes -gt 268435456) { throw 'Storage export exceeds the bounded 256MB backup limit; review quota/size before continuing.' }
Add-Type -AssemblyName System.Security
$protected = Get-Content -LiteralPath (Join-Path $private 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try { $keys = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) | ConvertFrom-Json }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$service = @($keys | Where-Object name -eq 'service_role')
if ($service.Count -ne 1) { throw 'Protected TEST server credential unavailable.' }
$client = [Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(45)
$client.DefaultRequestHeaders.Add('apikey', $service[0].api_key)
$client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $service[0].api_key)
$objectsDirectory = Join-Path $BackupDirectory 'storage'
New-Item -ItemType Directory -Path $objectsDirectory -Force | Out-Null
$records = @(); $failures = @(); $total = [long]0
try {
    foreach ($object in $before) {
        $response = $null; $stream = $null; $memory = $null
        try {
            if ($object.id -notmatch '^[0-9a-fA-F-]{36}$' -or $object.bucket -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid object identity.' }
            $parts = @($object.name.Split('/'))
            if ($parts | Where-Object { $_ -in @('.', '..', '') }) { throw 'Ambiguous object path.' }
            $path = ($parts | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
            $url = "https://$reference.supabase.co/storage/v1/object/authenticated/$($object.bucket)/$path"
            $response = $client.GetAsync($url, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) { throw ('Storage HTTP ' + [int]$response.StatusCode) }
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $memory = [IO.MemoryStream]::new(); $buffer = [byte[]]::new(8192)
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($memory.Length + $read -gt 16777216 -or $total + $memory.Length + $read -gt 268435456) { throw 'Bounded backup size exceeded.' }
                $memory.Write($buffer, 0, $read)
            }
            $bytes = $memory.ToArray()
            if ($object.size -and $bytes.Length -ne [long]$object.size) { throw 'Stored object size changed.' }
            if ($object.etag -and $response.Headers.ETag -and $object.etag.Trim('"') -cne $response.Headers.ETag.Tag.Trim('"')) { throw 'Stored object version changed.' }
            $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
            $sealed = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
            $output = Join-Path $objectsDirectory ($object.id + '.dpapi')
            [IO.File]::WriteAllBytes($output, $sealed)
            $recovered = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($output), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
            if ($hash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($recovered))) { throw 'Object encryption recovery hash mismatch.' }
            $total += $bytes.Length
            $records += [pscustomobject]@{ id=$object.id; bucket=$object.bucket; name=$object.name; updated=$object.updated; bytes=$bytes.Length; sha256=$hash; encrypted_sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash }
            [Array]::Clear($bytes,0,$bytes.Length); [Array]::Clear($recovered,0,$recovered.Length)
        } catch {
            # Object names, document contents and raw provider responses stay private.
            $failures += [pscustomobject]@{id=$object.id; error_type=$_.Exception.GetType().Name}
        } finally {
            if ($stream) { $stream.Dispose() }; if ($memory) { $memory.Dispose() }; if ($response) { $response.Dispose() }
        }
        Start-Sleep -Milliseconds 250
    }
} finally { $client.Dispose(); $keys=$null; $service=$null }
$after = @(Read-ObjectInventory 'storage-after.private.json')
$stable = ($before | ConvertTo-Json -Depth 6 -Compress) -ceq ($after | ConvertTo-Json -Depth 6 -Compress)
$verified = $stable -and $failures.Count -eq 0 -and $records.Count -eq $before.Count
@{objects=$records; failures=$failures; inventory_stable=$stable} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $BackupDirectory 'storage-manifest.private.json') -Encoding utf8
$summary = @{
    project=$reference; utc=[DateTime]::UtcNow.ToString('o'); object_count=$before.Count
    encrypted_objects=$records.Count; bytes=$total; failures=$failures.Count
    metadata_stable=$stable; object_bytes_integrity_verified=$verified
    encryption='Windows DPAPI CurrentUser; object names/IDs remain in the private manifest'
    limitations='Integrity/decryption checked. Uploading recovered objects into a Storage runtime and cross-machine DPAPI handover are not verified.'
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $repo 'docs/evidence/MASTER-storage-backup.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 6
if (-not $verified) { exit 1 }
