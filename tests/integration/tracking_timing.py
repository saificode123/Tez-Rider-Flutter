"""Clock-safe receipt sampling and finite-run summaries; no location storage."""
import datetime as dt
import json
import math
import statistics
import time


def receive_frame(socket, *, monotonic=time.monotonic,
                  utc_now=lambda: dt.datetime.now(dt.timezone.utc)):
    raw = socket.recv(timeout=1)
    # Sample after the blocking receive, before JSON decoding or other work.
    arrived = monotonic()
    wall = utc_now()
    return json.loads(raw), arrived, wall


def summarize(values):
    if not values:
        return {'samples': 0}
    if not all(math.isfinite(v) for v in values):
        raise ValueError('Finite measurements required')
    ordered = sorted(values)
    return {'samples': len(values), 'p50': statistics.median(ordered),
            'p95': ordered[math.ceil(len(ordered) * .95) - 1],
            'worst': ordered[-1]}
