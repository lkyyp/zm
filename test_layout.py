from pathlib import Path
from itertools import product
import plistlib

root = Path(__file__).resolve().parent
prefs = plistlib.loads((root/'AxsTwinDialPrefs/Resources/AxsTwinDialRoot.plist').read_bytes())
keys = {x['key']:x for x in prefs['items'] if 'key' in x}
assert keys['enabled']['default'] is False and keys['demoLyrics']['default'] is False
axes = lambda k: [keys[k]['min'], keys[k]['default'], keys[k]['max']]
count = 0
for w,h,s,t,x,y in product((230,320,390,430,768),(180,390,540,850),axes('playerScale'),axes('weatherScale'),axes('topX'),axes('topY')):
    left,right = min(w*.40,160)*s, min(w*.445,180)*t
    gap = min(46,w*.115)
    for safe in (0, 20, 54):
        fit = min(1,(w-56-gap)/(left+right),(h-safe-32)/max(left,right))
        l,r = left*fit,right*fit
        cy = safe+16+y+max(l,r)/2
        X = (w-l-r-gap)/2+x
        assert 15.99 <= X and X+l+gap+r <= w-15.99
        assert safe+3.99 <= cy-max(l,r)/2 and cy+max(l,r)/2 <= h-3.99
        assert l>0 and r>0 and gap>0
    count += 1
print(f'PASS {count} layout cases')
assets = root/'layout/Library/Application Support/AxsTwinDialResources.bundle'
assert set(x.name for x in assets.glob('*.png'))=={'previous.png','next.png','pause.png'}
for x in assets.glob('*.png'):
    assert x.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
print('PASS 3 packaged PNG resources')
