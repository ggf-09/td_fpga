import unittest,tempfile,sys,struct,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent.parent/'doc/convert'))
from prepare_scrolling_lyrics import wrap_line,write_track,KEY
from generate_music_lyrics import read_lrc

class ScrollingCard(unittest.TestCase):
 def test_balanced_english_words(self):
  text="I just wanna be there where you are"
  rows=list(wrap_line(0,text,list(range(len(text)))))
  self.assertEqual(' '.join(t for _,t,_ in rows),text)
  self.assertTrue(all(len(t)<=31 for _,t,_ in rows))
  self.assertNotIn('are',[t for _,t,_ in rows])
 def test_contractions_survive(self):
  text="It's where you're going and you’re staying now"
  rows=list(wrap_line(0,text,list(range(len(text)))))
  self.assertEqual(' '.join(t for _,t,_ in rows),text)
 def test_long_word_rejected(self):
  with self.assertRaisesRegex(ValueError,'English word'):list(wrap_line(0,'a'*32,[0]*32))
 def test_long_time_gap_gets_another_row(self):
  rows=list(wrap_line(0,'甲乙',[0,11000]))
  self.assertEqual([(s,t) for s,t,_ in rows],[(0,'甲'),(11000,'乙')])
 def test_spaces_removed_with_matching_times(self):
  rows=list(wrap_line(0,' abc ',[0,10,20,30,40]))
  self.assertEqual(rows,[(0,'abc',[10,20,30])])
 def test_exact_krc_quantization(self):
  with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
   tmp=Path(tmp);src=tmp/'input.krc'
   clear='[1000,1200]<0,300,0>你<333,200,0>好<700,400,0>呀\n'
   compressed=zlib.compress(clear.encode());src.write_bytes(b'krc1'+bytes(v^KEY[i%16] for i,v in enumerate(compressed)))
   info=write_track(src,'测试',tmp/'SONG1.LRC',tmp/'FONT.BIN');bank=(tmp/'FONT.BIN').read_bytes()
   self.assertEqual(bank[8712:8720],b'LKT1'+struct.pack('<HBB',3,4,1))
   self.assertEqual(bank[9216:9219],bytes([0,9,18]))
   self.assertEqual(info['timing'],'KRC');self.assertEqual(len(bank),16384)
 def test_estimated_lrc_is_labelled(self):
  with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
   tmp=Path(tmp);src=tmp/'input.lrc';src.write_text('[00:01.00]你好\n[00:03.00]再见\n',encoding='utf-8')
   info=write_track(src,'测试',tmp/'SONG1.LRC',tmp/'FONT.BIN')
   self.assertEqual((tmp/'FONT.BIN').read_bytes()[8719],2)
   self.assertEqual(info['timing'],'estimated LRC')
 def test_bad_krc_rejected(self):
  with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
   tmp=Path(tmp);src=tmp/'bad.krc';src.write_bytes(b'bad!')
   with self.assertRaisesRegex(ValueError,'signature'):write_track(src,'测试',tmp/'SONG1.LRC',tmp/'FONT.BIN')
 def test_all_sixteen_banks_match_text(self):
  fixture=ROOT/'fixtures/scroll_lyrics';font=(fixture/'FONT.BIN').read_bytes()
  self.assertEqual(len(font),262144)
  for n in range(1,17):
   bank=font[(n-1)*16384:n*16384];lrc=fixture/f'SONG{n}.LRC'
   lines=read_lrc(lrc,max_chars=31);text=''.join(t for _,t in lines)
   self.assertEqual(bank[8712:8716],b'LKT1');self.assertEqual(int.from_bytes(bank[8716:8718],'little'),len(text))
   self.assertEqual(bank[8718],4);self.assertEqual(bank[8719],1)
   glyphs={int.from_bytes(bank[8+i*2:10+i*2],'little') for i in range(int.from_bytes(bank[5:7],'little'))}
   self.assertTrue(all(ord(c) in glyphs for c in text))
   self.assertLessEqual(len(text),3072);self.assertLessEqual(len(lines),158);self.assertLessEqual(lrc.stat().st_size,4096)
 def test_first_two_use_real_krc_timing(self):
  fixture=ROOT/'fixtures/scroll_lyrics';font=(fixture/'FONT.BIN').read_bytes()
  for n,cs,expected_ms in [(1,11181,3280),(2,15345,4200)]:
   entries=read_lrc(fixture/f'SONG{n}.LRC',max_chars=31)
   index=next(i for i,(start,_) in enumerate(entries) if start==cs)
   offset=sum(len(text) for _,text in entries[:index])+len(entries[index][1])-1
   bank=font[(n-1)*16384:n*16384]
   self.assertEqual(bank[9216+offset]*40,expected_ms)
   self.assertLess(bank[9216+offset]*40,8000)
 def test_complete_sugar_words(self):
  rows=read_lrc(ROOT/'fixtures/scroll_lyrics/SONG13.LRC',max_chars=31)
  self.assertEqual(len(rows),132)
  text=' '.join(t for _,t in rows)
  self.assertIn("where you are",text);self.assertIn("I'm broken down",text)
  self.assertTrue(all(t not in ['ar','e','are'] for _,t in rows))

if __name__=='__main__':unittest.main()
