"""Reuse bounded device actions while keeping this repair's evidence separate."""
from pathlib import Path

helper = Path(__file__).with_name('FRONTEND-native.py')
source = helper.read_text(encoding='utf-8')
source = source.replace("OUT = ROOT / '.fr21-local/frontend'", "OUT = ROOT / '.fr21-local/repair-native'")
source = source.replace("('FRONTEND-' + name + '.png')", "('REPAIR-' + name + '.png')")
exec(compile(source, str(helper), 'exec'), {'__file__': str(helper.resolve())})
