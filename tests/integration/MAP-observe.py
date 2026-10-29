"""Use existing real TEST observers; keep historical evidence immutable."""
import importlib.util
from pathlib import Path
import sys

action = sys.argv[1]
assert action in ('delivery','gps','route','stopped')
file = 'AUTH-single-order-inspect.py' if action == 'delivery' else 'AUTH-delivery-observe.py'
spec = importlib.util.spec_from_file_location('map_current_observer', Path(__file__).with_name(file))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if action == 'delivery':
    module.main(evidence='MAP-order-state.json')
else:
    module.main(action, prefix='MAP-')
