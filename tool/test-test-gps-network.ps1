[CmdletBinding()]
param(
    [ValidateRange(60, 120)][int]$OfflineSeconds = 90,
    [ValidateSet('MASTER-gps-network.json','RELEASE-gps-network.json')][string]$EvidenceName = 'MASTER-gps-network.json'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$adb = 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
$serial = 'AESWNRBAEUPNTGJZ'; $package = 'com.example.flutter_application_1.fr21test'
function Phone([string[]]$Arguments) {
    $result = & $adb -s $serial @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Authorized TEST phone command failed.' }
    return ($result -join "`n").Trim()
}
$top = Phone @('shell','dumpsys','activity','activities')
if ($top -notmatch 'topResumedActivity=ActivityRecord\{[^}]*com.android.launcher/') {
    throw 'Background TEST measurement requires the previously selected launcher; another app may be in use.'
}
$process = Phone @('shell','pidof',$package)
if ($process -notmatch '^\d+$') { throw 'One running TEST process required.' }
$services = Phone @('shell','dumpsys','activity','services',$package)
if ($services -notmatch 'GeolocatorLocationService' -or $services -notmatch 'isForeground=true') { throw 'Active TEST location foreground service required.' }
$wifi = Phone @('shell','settings','get','global','wifi_on')
$mobile = Phone @('shell','settings','get','global','mobile_data')
if ($wifi -notin @('0','1') -or $mobile -notin @('0','1') -or ($wifi -eq '0' -and $mobile -eq '0')) { throw 'Known connected network settings required; no network setting changed.' }
$clock = [Diagnostics.Stopwatch]::StartNew()
$record = [ordered]@{ device=$serial; package=$package; process_before=$process; original_wifi=$wifi; original_mobile=$mobile; network_absent_observed=$false; settings_restored=$false; same_process=$false }
try {
    Phone @('shell','svc','wifi','disable') | Out-Null
    Phone @('shell','svc','data','disable') | Out-Null
    $remaining = $OfflineSeconds
    while ($remaining -gt 0) {
        $chunk = [Math]::Min(30,$remaining)
        Start-Sleep -Seconds $chunk
        $remaining -= $chunk
        $connectivity = Phone @('shell','dumpsys','connectivity')
        if ($connectivity -match 'Active default network:\s*(none|null)\b') { $record.network_absent_observed=$true }
    }
    $record.offline_window_ms=$clock.ElapsedMilliseconds
} finally {
    Phone @('shell','svc','wifi',$(if ($wifi -eq '1') {'enable'} else {'disable'})) | Out-Null
    Phone @('shell','svc','data',$(if ($mobile -eq '1') {'enable'} else {'disable'})) | Out-Null
    $record.settings_restored=(Phone @('shell','settings','get','global','wifi_on')) -eq $wifi -and (Phone @('shell','settings','get','global','mobile_data')) -eq $mobile
    $record.same_process=(Phone @('shell','pidof',$package)) -eq $process
    $record.utc=[DateTime]::UtcNow.ToString('o')
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repo ('docs/evidence/' + $EvidenceName)) -Encoding utf8
}
$record | ConvertTo-Json
if (-not $record.settings_restored -or -not $record.same_process -or -not $record.network_absent_observed) { exit 1 }
