import unittest,tempfile,sys,hashlib
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent.parent/'doc/convert'))
from prepare_library_menu import build_menu,wrap_title
class MenuCard(unittest.TestCase):
 def test_missing_covers_create_valid_atlas(self):
  with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
   tmp=Path(tmp);out=tmp/'MENU.BMP';titles=build_menu(tmp,out)
   self.assertEqual(titles[0],'SONG 01');self.assertEqual(titles[-1],'SONG 16')
   raw=out.read_bytes();self.assertEqual(len(raw),921654);self.assertEqual(raw[:2],b'BM')
   self.assertEqual(int.from_bytes(raw[28:30],'little'),24)
   with Image.open(out) as im:self.assertEqual(im.size,(640,480));self.assertEqual(im.mode,'RGB')
 def test_source_unicode_title_and_cover_remain_unchanged(self):
  with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
   tmp=Path(tmp);lrc=tmp/'SONG1.LRC';lrc.write_text('[ti:牵丝戏]\n[00:01.00]你\n',encoding='utf-8')
   pic=tmp/'PIC1.BMP';Image.new('RGB',(640,480),(255,0,0)).save(pic)
   original={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [lrc,pic]}
   self.assertEqual(build_menu(tmp,tmp/'MENU.BMP')[0],'牵丝戏')
   self.assertTrue(all(hashlib.sha256((tmp/n).read_bytes()).hexdigest()==v for n,v in original.items()))
   with Image.open(tmp/'MENU.BMP') as im:self.assertEqual(im.getpixel((80,40)),(255,0,0))
 def test_maximum_title_fits_without_truncation(self):
  font=ImageFont.truetype('C:/Windows/Fonts/simsun.ttc',12);draw=ImageDraw.Draw(Image.new('RGB',(160,120)))
  title='歌'*31;rows=wrap_title(draw,title,font,148)
  self.assertEqual(''.join(rows),title);self.assertLessEqual(len(rows),3)
  self.assertTrue(all(draw.textlength(r,font=font)<=148 for r in rows))
if __name__=='__main__':unittest.main()
