"""CI-only inspection of the Xcode build. No launch or registration."""
from pathlib import Path
import plistlib
import sys
app = Path(sys.argv[1])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleDisplayName'] == 'iStickies2'
assert info['CFBundleIdentifier'] == 'dev.douyixuan.stickies'
assert info['CFBundleIconFile'] == 'iStickies2.icns'
icon = app/'Contents/Resources/iStickies2.icns'
assert icon.read_bytes() == Path('Assets/iStickies2.icns').read_bytes()
print('PASS: Xcode product contains the actual icon and retains production identity')
