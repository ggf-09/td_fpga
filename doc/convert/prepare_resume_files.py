"""Create the two preallocated progress files; existing records are preserved.

Usage: python prepare_resume_files.py E:/
       python prepare_resume_files.py E:/ --reset
Remove/eject the card from the PC before using it in the FPGA player.
"""
from pathlib import Path
import argparse,os,struct,zlib
def prepare(directory,reset=False):
 directory=Path(directory)
 if not directory.is_dir():raise ValueError('Target directory does not exist')
 for name in ('RESUMA.BIN','RESUMB.BIN'):
  p=directory/name
  if p.exists() and not reset:
   if p.stat().st_size!=512:raise ValueError(f'{p}: expected exactly 512 bytes; use --reset to replace')
   print('Preserved',p);continue
  with p.open('wb') as f:f.write(bytes(512));f.flush();os.fsync(f.fileno())
  print('Created',p,'512 bytes')
if __name__=='__main__':
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('directory');ap.add_argument('--reset',action='store_true',help='Clear existing playback progress')
 a=ap.parse_args();prepare(a.directory,a.reset)
