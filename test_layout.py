from pathlib import Path
from itertools import product
import plistlib

root = Path(__file__).resolve().parent
prefs = plistlib.loads((root/'AxsTwinDialPrefs/Resources/AxsTwinDialRoot.plist').read_bytes())
keys = {x['key']:x for x in prefs['items'] if 'key' in x}
assert keys['enabled']['default'] is False and keys['demoLyrics']['default'] is False
axes = lambda k: [keys[k]['min'], keys[k]['default'], keys[k]['max']]
count = 0
for w,h,s,t,x,y in product((230,320,390,430,768),(180,390,540,850),axes('playerScale'),axes('weatherScale'),axes('horizontal'),axes('vertical')):
    left,right = min(w*.40,160)*s, min(w*.445,180)*t
    gap = min(46,w*.115)
    fit = min(1,(w-56-gap)/(left+right),(h-16)/max(left,right))
    left,right = left*fit,right*fit
    margin = max(left,right)/2+8
    cy = margin+(h-2*margin)*((y-.15)/.70)
    if h-2*margin > 1e-6 and y<.8499:
        assert margin+(h-2*margin)*((y+.0001-.15)/.70)>cy
    X = 10+(w-left-right-gap-20)*x
    assert 9.99 <= X and X+left+gap+right <= w-9.99
    assert 7.99 <= cy-max(left,right)/2 and cy+max(left,right)/2 <= h-7.99
    assert left>0 and right>0 and gap>0
    assert 10+(w-left-right-gap-20)>10
    count += 1
print(f'PASS {count} layout cases')
assets = root/'layout/Library/Application Support/AxsTwinDialResources.bundle'
assert set(x.name for x in assets.glob('*.png'))=={'previous.png','next.png','pause.png'}
for x in assets.glob('*.png'):
    assert x.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
print('PASS 3 packaged PNG resources')
