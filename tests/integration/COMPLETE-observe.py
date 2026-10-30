"""Read-only observation of genuine order 3180; never signs in as its Rider."""
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('complete_observer', Path(__file__).with_name('AUTH-delivery-observe.py'))
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)
mode = sys.argv[1]
assert mode in ('gps','travel','stopped')  # Routing verification uses the normal physical app only.
observer.main(mode, prefix='COMPLETE-', capture_seconds=300 if mode=='gps'else None)
