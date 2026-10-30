"""Scoped native build verification; no password entry or lifecycle mutations."""
from pathlib import Path
import sys

assert sys.argv[1] in ('install','installed-proof','launch','status','resume','scroll','scroll-up','back','cleanup')
helper = Path(__file__).with_name('FRONTEND-native.py')
source = helper.read_text(encoding='utf-8')
source = source.replace("OUT = ROOT / '.fr21-local/frontend'", "OUT = ROOT / '.fr21-local/complete-native'")
source = source.replace("('FRONTEND-' + name + '.png')", "('COMPLETE-' + name + '.png')")
exec(compile(source,str(helper),'exec'),{'__file__':str(helper.resolve())})
