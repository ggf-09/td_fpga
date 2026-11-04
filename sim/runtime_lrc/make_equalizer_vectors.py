from pathlib import Path
import math,random,json
random.seed(20261015)
gains=[128,181,256,362,512]
lo=[0,0];hi=[0,0];smooth=[256]*4
rows=[];freq_sections=[];clip_count=0
def frame(l,r,b=2,m=2,t=2,v=16,clear=False):
 global lo,hi,smooth,clip_count
 if clear:lo=[0,0];hi=[0,0];smooth=[256]*4
 targets=[gains[b],gains[m],gains[t],v*16]
 smooth=[x+(y>x)-(y<x) for x,y in zip(smooth,targets)]
 out=[];clipped=0
 for ch,sample in enumerate([l,r]):
  x=sample*256
  lo[ch]+=((x-lo[ch])*1693)//65536
  hi[ch]+=((x-hi[ch])*26713)//65536
  total=lo[ch]*smooth[0]+(hi[ch]-lo[ch])*smooth[1]+(x-hi[ch])*smooth[2]
  y=((total//256)*smooth[3])//65536
  if y>32767 or y< -32768:clipped=1
  out.append(max(-32768,min(32767,y)))
 if clipped:clip_count+=1
 rows.append((l,r,b,m,t,v,int(clear),*out,clipped))
# Exact transparent neutral response, independent stereo, signed extremes.
for i in range(1024):
 l=[-32768,32767,0,-1,1][i%5] if i<100 else random.randint(-32768,32767)
 frame(l,random.randint(-32768,32767),clear=i==0)
# Non-neutral fixed-point output, gain slew, all settings and volume levels.
for i in range(4096):
 b,m,t=[random.randrange(5) for _ in range(3)] if i%100==0 else (b,m,t)
 v=(i//200)%17
 frame(random.randint(-32768,32767),random.randint(-32768,32767),b,m,t,v)
# Enough full-scale samples to reach both saturation limits.
for i in range(600):frame(30000,-30000,4,4,4,16,clear=i==0)
for i in range(600):frame(30000,-30000,4,4,4,0)
for band,freq in enumerate([100,1000,10000]):
 for setting in [2,0,4]:
  start=len(rows)
  for n in range(4096):
   gain=[2,2,2];gain[band]=setting
   l=round(4000*math.sin(2*math.pi*freq*n/48000))
   # Different right signal proves states are not shared across channels.
   r=round(2700*math.sin(2*math.pi*(freq+173)*n/48000))
   frame(l,r,*gain,16,clear=n==0)
  freq_sections.append(dict(band=band,frequency=freq,setting=setting,start=start,stop=len(rows)))
Path('equalizer_vectors.txt').write_text(''.join(' '.join(map(str,row))+'\n' for row in rows),encoding='ascii')
Path('equalizer_sections.json').write_text(json.dumps(freq_sections),encoding='ascii')
print(f'Generated {len(rows)} EQ stereo reference frames, {clip_count} saturating frames',flush=True)
