from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parent
with Image.open(root/'fixtures/menu_browser/MENU.BMP') as im:
 im=im.convert('RGB');assert im.size==(640,480)
 (root/'menu_atlas.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in im.getdata()),encoding='ascii')
print('Prepared real menu card pixels')
