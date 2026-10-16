"""Reuse the accepted streaming APK/source credential scanner for FR17."""
from pathlib import Path
path=Path(__file__).with_name('FR-10-artifact.py')
source=path.read_text(encoding='utf-8-sig')
replacements={
 "ROOT / '.fr21-local/fr10'":"ROOT / '.fr21-local/fr17'",
 "['fr10-accounts.bin','fr30-accounts.bin']":"['fr10-accounts.bin','fr30-accounts.bin','fr17-accounts.bin']",
 "b'fr10_checkout',b'fr10_vendor_transition'":"b'fr10_checkout',b'vendor_adjust_stock',b'fr17_save_product',b'stock_qty'",
 "'fr10_code_present'":"'fr17_code_present'",
}
for before,after in replacements.items():
    assert source.count(before)==1,'Review changed base artifact scanner'
    source=source.replace(before,after)
exec(compile(source,str(path),'exec'))
