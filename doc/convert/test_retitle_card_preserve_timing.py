import hashlib,json,struct,sys,tempfile,unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import retitle_card_preserve_timing as retitle
from generate_music_lyrics import read_lrc
from prepare_music_card import read_card_title,write_card_font

def make_card(folder,artists):
    """Temporary fake card: 16 PICs, 16 titled LRCs, FONT.BIN with LKT1 tails."""
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True);banks=bytearray()
    with tempfile.TemporaryDirectory(dir=folder) as scratch:
        for n in range(1,17):
            Image.new('RGB',(640,480),(n*7%256,40,90)).save(folder/f'PIC{n}.BMP',format='BMP')
            lrc=folder/f'SONG{n}.LRC'
            lrc.write_bytes((f'[ti:曲{n}]\n[00:01.00]你好世界{n}\n[00:05.50]第二句歌词\n'
                             '[01:00.00](完)\n').encode('utf-8'))
            slot=Path(scratch)/f'slot{n}.bin'
            glyphs=write_card_font([lrc],slot)
            bank=bytearray(slot.read_bytes())
            bank.extend(bytes(16384-len(bank)))
            payload=bytes((n+i)%256 for i in range(6))
            bank[8712:8720]=b'LKT1'+struct.pack('<HBB',len(payload),4,2)
            bank[9216:9216+len(payload)]=payload
            bank[-16:]=bytes(range(n,n+16))
            banks.extend(bank)
    (folder/'FONT.BIN').write_bytes(bytes(banks))
    (folder/'artists.json').write_text(json.dumps({str(n):a for n,a in artists.items()},
                                                  ensure_ascii=False),encoding='utf-8')
    return folder

class RetitleCard(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
     cls.tmp=tempfile.TemporaryDirectory()
     cls.card=make_card(Path(cls.tmp.name)/'card',{n:f'歌手{n}' for n in range(1,17)})
     cls.out=Path(cls.tmp.name)/'staging'
     cls.report=retitle.build(cls.card,cls.out,cls.card/'artists.json')
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def test_titles_gain_artist(self):
     for n in range(1,17):
         self.assertEqual(read_card_title(self.out/f'SONG{n}.LRC'),f'曲{n} - 歌手{n}')
         self.assertLessEqual(len(f'曲{n} - 歌手{n}'),31)
 def test_lyrics_and_timestamps_byte_identical(self):
     for n in range(1,17):
         old=(self.card/f'SONG{n}.LRC').read_bytes();new=(self.out/f'SONG{n}.LRC').read_bytes()
         self.assertEqual(old.split(b'\n',1)[1],new.split(b'\n',1)[1])
         self.assertEqual(read_lrc(self.card/f'SONG{n}.LRC',max_chars=31),
                          read_lrc(self.out/f'SONG{n}.LRC',max_chars=31))
 def test_lrc_size_limit(self):
     for n in range(1,17):self.assertLessEqual((self.out/f'SONG{n}.LRC').stat().st_size,4096)
 def test_lkt1_tail_verbatim_all_banks(self):
     src=(self.card/'FONT.BIN').read_bytes();staged=(self.out/'FONT.BIN').read_bytes()
     self.assertEqual(len(staged),16*16384)
     for n in range(1,17):
         self.assertEqual(staged[(n-1)*16384+8712:n*16384],
                          src[(n-1)*16384+8712:n*16384],f'bank {n} tail changed')
 def test_glyph_capacity_and_artist_coverage(self):
     staged=(self.out/'FONT.BIN').read_bytes()
     for n in range(1,17):
         bank=staged[(n-1)*16384:n*16384]
         count=int.from_bytes(bank[5:7],'little')
         self.assertLessEqual(count,256)
         charset={int.from_bytes(bank[8+i*2:10+i*2],'little') for i in range(count)}
         for c in f'曲{n} - 歌手{n}':self.assertIn(ord(c),charset)
         self.assertEqual(self.report['tracks'][n]['glyphs'],count)
 def test_menu_bmp_built(self):
     menu=self.out/'MENU.BMP';self.assertTrue(menu.is_file())
     self.assertEqual(menu.stat().st_size,921654)
 def test_card_untouched(self):
     digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
     for n in range(1,17):
         self.assertEqual(digest(self.card/f'SONG{n}.LRC'),
                          digest(Path(self.tmp.name)/'card'/f'SONG{n}.LRC'))
         self.assertEqual((self.card/f'SONG{n}.LRC').read_bytes()[:4],b'[ti:')
     self.assertNotEqual((self.card/'FONT.BIN').read_bytes(),(self.out/'FONT.BIN').read_bytes())
 def test_artist_suffix_is_not_duplicated(self):
     self.assertEqual(retitle.artist_title('曲1','歌手1'),'曲1 - 歌手1')
     self.assertEqual(retitle.artist_title('曲1 - 歌手1','歌手1'),'曲1 - 歌手1')
 def test_overlong_title_rejected(self):
     with tempfile.TemporaryDirectory() as tmp:
         tmp=Path(tmp)
         card=make_card(tmp/'card',{n:'超' * 40 for n in range(1,17)})
         with self.assertRaisesRegex(ValueError,'31'):
             retitle.build(card,tmp/'out',card/'artists.json')
 def test_output_not_on_card_rejected(self):
     with self.assertRaisesRegex(ValueError,'separate'):
         retitle.build(self.card,self.card/'sub',self.card/'artists.json')

if __name__=='__main__':unittest.main()
