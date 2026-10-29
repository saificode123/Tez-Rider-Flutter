"""Publish only qualified numeric samples from completed physical TEST captures."""
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/evidence'
CAPTURE = ROOT / '.fr21-local/release-gps'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def summary(values):
    ordered = sorted(values)
    return {'samples': len(values), 'p50': round(statistics.median(values), 3),
            'p95': ordered[math.ceil(len(values) * .95) - 1], 'worst': max(values)} if values else {'samples': 0}


def main():
    windows = {}
    for phase, observer, pipeline in (
        ('power-saving', 'power-saving-observer', 'power-saving-pipeline'),
        ('indoor-normal', 'indoor-normal-observer', 'indoor-normal-pipeline'),
        ('outdoor-transition', 'outdoor-transition-observer', 'outdoor-transition-pipeline'),
        ('outdoor-foreground', 'physical-observer-foreground', 'pipeline-foreground'),
        ('outdoor-background', 'physical-observer-background', 'pipeline-background'),
        ('recovery', 'physical-observer-recovery', 'pipeline-recovery'),
    ):
        observed = read(CAPTURE / (observer + '.json'))
        measured = read(CAPTURE / (pipeline + '.json'))
        assert observed['observer_status'] == 'COMPLETED' and observed['duplicates'] == 0
        intervals = observed['intervals_seconds']
        windows[phase] = {'utc': observed['reported_at_utc'], 'seconds': observed['seconds'],
                         'events': observed['events'], 'duplicates': 0,
                         'customer_receipt_intervals_seconds': summary(intervals),
                         'pipeline_stages_ms': {k: summary(v) for k, v in measured['metrics_ms'].items()}}
    route = read(CAPTURE / 'routes.json')
    assert all(r['http_status'] == 200 and r['road_geometry'] and not r['is_approximate'] for r in route['requests'])
    built = read(ROOT / 'build/delivery/test/build-evidence.json')
    for source in built['sources']:
        assert hashlib.sha256((ROOT / source['path']).read_bytes()).hexdigest().upper() == source['sha256'].upper()
    artifact = hashlib.sha256((ROOT / 'build/delivery/test/app-fr21test-debug.apk').read_bytes()).hexdigest().upper()
    assert artifact == 'F5F18E26D1F863FFFD33DBB33BDBE7EEA6206C0DE7E88EB7DB3AD0DA5A910D04'
    record = {'project': 'igeisilhtmglgnqvllrx', 'generated_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'artifact_sha256': artifact, 'build_source_files_still_match': len(built['sources']),
              'percentile_method': 'Nearest rank p95; arithmetic median p50. Small bounded samples, not fleet or load qualification.',
              'gps_windows': windows,
              'routing': {'utc': route['utc'], 'dns_probe_ms': route['dns_probe_ms'],
                          'initial_connect_tls_ms': route['initial_connect_tls_ms'],
                          'http_request_ms': summary([r['request_ms'] for r in route['requests']]),
                          'warm_cache_http_request_ms': summary([r['request_ms'] for r in route['requests'][1:]]),
                          'json_decode_ms': summary([r['json_decode_ms'] for r in route['requests']]),
                          'samples': route['requests']},
              'acceptance': {'strict_gps_2_to_3_seconds': 'PARTIAL: receipt outliers exceed 3 seconds',
                             'route_800_ms': 'FAIL: both observed median and p95 exceed target'},
              'scope': 'Stationary OPPO Android 13 DEBUG TEST. Observer/pipeline windows captured separately. No coordinates, absolute fix timestamps, summed jitter distance or uncertain cross-device latency included. No road movement, iOS, render latency or load claim. Physical GPS windows precede the final body-size parser patch; authorization/publication pipeline unchanged.'}
    (OUT / 'RELEASE-performance.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    paths = ['_shared/fr28-access.ts', '_shared/security-runtime.ts', 'fr13-location/handler.ts',
             'fr13-location/index.ts', 'fr13-location/publication.ts', 'get-delivery-route/handler.ts', 'get-delivery-route/index.ts']
    checks = []
    for path in paths:
        local = (ROOT / 'supabase/functions' / path).read_bytes()
        deployed = (ROOT / '.fr21-local/release-remote/supabase/functions' / path).read_bytes()
        assert local == deployed, 'Downloaded TEST function differs: ' + path
        checks.append({'path': path, 'sha256': hashlib.sha256(local).hexdigest(), 'matches': True})
    (OUT / 'RELEASE-deployed-source.json').write_text(json.dumps({
        'project': 'igeisilhtmglgnqvllrx', 'verified_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'downloaded_source_checks': checks,
        'scope': 'Read-only API download of final TEST bundles including the bounded body parser and shared security dependencies; current local byte equality.'}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'physical_windows': len(windows), 'source_files_matched': len(built['sources']), 'deployed_files_matched': len(checks)}))


if __name__ == '__main__':
    main()
