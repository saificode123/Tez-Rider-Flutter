param([string]$OutputDirectory = 'build/fr21-reviewed-plan')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $repo
$manifest = Get-Content -LiteralPath 'supabase/test-environment/FR-21-reviewed-manifest.json' -Raw | ConvertFrom-Json
if ($manifest.project_ref -cne 'igeisilhtmglgnqvllrx') { throw 'Manifest target mismatch' }
if ((Get-FileHash -LiteralPath 'schema-export/tezrider-schema.sql').Hash -ine $manifest.source_schema_sha256) {
    throw 'Authoritative source changed; revalidate before preparing'
}
foreach ($migration in $manifest.migrations) {
    if ((Get-FileHash -LiteralPath (Join-Path 'supabase/migrations' $migration.file)).Hash -ine $migration.sha256) {
        throw "Reviewed migration changed: $($migration.file)"
    }
}
$output = [IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
$allowed = [IO.Path]::GetFullPath((Join-Path $repo 'build')) + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Preparation output must remain inside the ignored build directory.'
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($migration in $manifest.migrations) {
    Copy-Item -LiteralPath (Join-Path 'supabase/migrations' $migration.file) -Destination $output
}
# The existing role tests are transactional. Exclude psql directives and the
# committed, LOCAL-ONLY dblink race section; never weaken its database guard.
$tests = Get-Content -LiteralPath 'supabase/tests/FR-21.sql' -Raw
$start = $tests.IndexOf("begin;`n", [StringComparison]::Ordinal)
if ($start -lt 0) { $start = $tests.IndexOf("begin;`r`n", [StringComparison]::Ordinal) }
$end = $tests.IndexOf('rollback;', $start, [StringComparison]::Ordinal)
if ($start -lt 0 -or $end -lt $start) { throw 'Transactional SQL test boundaries changed.' }
$transaction = $tests.Substring($start, $end + 'rollback;'.Length - $start)
if ($transaction -match '(?m)^\\') { throw 'Unexpected psql directive in hosted test body.' }
$header = "-- TEST ONLY: igeisilhtmglgnqvllrx. Synthetic records; all changes roll back.`n-- Requires explicit TEST write approval and verified target before execution.`n"
[IO.File]::WriteAllText((Join-Path $output 'FR-21-hosted-transaction.sql'), $header + $transaction + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "Prepared reviewed SQL in $output. No database connection or write performed."
