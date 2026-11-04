from pathlib import Path
import json,math
samples=[tuple(map(int,line.split())) for line in Path('equalizer_results.txt').read_text().splitlines()]
sections=json.loads(Path('equalizer_sections.json').read_text())
levels={};report=[]
for s in sections:
 xs=[row[0] for row in samples[s['start']+1024:s['stop']]]
 rms=math.sqrt(sum(x*x for x in xs)/len(xs))
 levels[s['band'],s['setting']]=rms
for band,f in enumerate([100,1000,10000]):
 base=levels[band,2]
 cut=20*math.log10(levels[band,0]/base)
 boost=20*math.log10(levels[band,4]/base)
 assert cut < -2.5 and boost > 3.5,(f,cut,boost)
 assert abs(20*math.log10(base/(4000/math.sqrt(2))))<0.1
 report.append(dict(frequency_hz=f,cut_db=round(cut,3),boost_db=round(boost,3)))
assert any(l==32767 and r==-32768 for l,r in samples),'both saturation limits must be exercised'
Path('equalizer_response.json').write_text(json.dumps(report,indent=2),encoding='ascii')
print('PASS measured 48 kHz EQ frequency response:',json.dumps(report),flush=True)
