"""Word-safe LRC rows plus compact KRC timings in each FONT.BIN slot.

Timing extension: bytes 8712..8719 = LKT1/count:u16/quantum:4/quality,
bytes 9216..12287 = one 40-ms relative start per displayed character.
Quality 1 uses KRC timing; 2 estimates from LRC line timing.
"""
from pathlib import Path
import re,zlib,struct
from prepare_music_card import normalize_card_lrc,write_card_font,read_card_title
from generate_music_lyrics import read_lrc

KEY=bytes([64,71,97,119,94,50,116,71,81,54,49,45,206,210,110,105])
TOKEN=re.compile(r"<(\d+),(\d+),(\d+)>")
def decode_krc(path):
    raw=Path(path).read_bytes()
    if raw[:4]!=b"krc1":raise ValueError("KRC signature mismatch")
    return zlib.decompress(bytes(b^KEY[i%16] for i,b in enumerate(raw[4:]))).decode("utf-8-sig")
def ascii_word(c):
    return (c.isascii() and c.isalnum()) or c in "'’_-"
def safe_cut(text,limit):
    cut=min(limit,len(text))
    if cut<len(text) and ascii_word(text[cut-1]) and ascii_word(text[cut]):
        while cut and ascii_word(text[cut-1]):cut-=1
        if not cut:raise ValueError("An English word exceeds the 31-character row capacity")
    return cut

def wrap_line(start,text,times):
    """Yield word-safe rows with their original character start times."""
    if len(text)!=len(times):raise ValueError("text/timing length mismatch")
    while text:
        while text and text[0].isspace():text=text[1:];times=times[1:]
        if not text:break
        limit=min(31,len(text))
        for i in range(1,limit):
            if times[i]-start>10200:limit=i;break
        cut=safe_cut(text,limit)
        if len(text)>31 and limit==31:
            chunks=(len(text)+30)//31;target=(len(text)+chunks-1)//chunks
            choices=[i for i in range(1,limit+1) if
                     not (ascii_word(text[i-1]) and ascii_word(text[i])) and
                     len(text)-i <= 31*(chunks-1)]
            if choices:cut=min(choices,key=lambda i:abs(i-target))
        row=text[:cut].rstrip();rt=times[:len(row)]
        if not row:raise ValueError("Empty wrapped row")
        yield start,row,rt
        text=text[cut:];times=times[cut:]
        if times:start=times[0]

def krc_rows(path):
    source=decode_krc(path)
    m=re.search(r"^\[offset:([+-]?\d+)\]",source,re.M);offset=int(m[1]) if m else 0
    m=re.search(r"^\[manualoffset:([+-]?\d+)\]",source,re.M)
    if m and int(m[1]):raise ValueError("Nonzero manual offset requires explicit handling")
    rows=[];all_original=[]
    for line in source.splitlines():
        m=re.match(r"^\[(\d+),(\d+)\](.*)",line)
        if not m:continue
        start=int(m[1])+offset;body=m[3];tags=list(TOKEN.finditer(body))
        text="";times=[]
        if tags:
            prefix=body[:tags[0].start()];text+=prefix;times += [start]*len(prefix)
            for i,tag in enumerate(tags):
                part=body[tag.end():tags[i+1].start() if i+1<len(tags) else len(body)]
                text+=part;times += [start+int(tag[1])]*len(part)
        else:text=body;times=[start]*len(text)
        if not text.strip():continue
        all_original.append(text)
        rows.extend(wrap_line(max(0,start),text,times))
    if ''.join(c for s in all_original for c in s if not c.isspace()) != ''.join(c for _,s,_ in rows for c in s if not c.isspace()):
        raise ValueError("Wrapping lost text")
    return rows,1

def lrc_rows(path):
    entries=read_lrc(Path(path),max_chars=4096);rows=[]
    for i,(cs,text) in enumerate(entries):
        end=entries[i+1][0] if i+1<len(entries) else cs+800
        duration=max(1,min(end-cs,800))*10
        times=[cs*10+duration*j//max(1,len(text)) for j in range(len(text))]
        rows.extend(wrap_line(cs*10,text,times))
    return rows,2

def write_track(source,title,destination,font_destination):
    rows,quality=krc_rows(source) if Path(source).suffix.lower()=='.krc' else lrc_rows(source)
    rows.sort(key=lambda r:r[0])
    # Separate simultaneous credit lines without overwriting sung text.
    adjusted=[];i=0
    while i<len(rows):
        cs=rows[i][0]//10;j=i+1
        while j<len(rows) and rows[j][0]//10==cs:j+=1
        first=max(adjusted[-1][0]+1 if adjusted else 0,cs-(j-i)+1)
        adjusted.extend((first+k,text,times) for k,(_,text,times) in enumerate(rows[i:j]));i=j
    payload=bytearray()
    for cs,text,times in adjusted:
        for ms in times:
            tick=(max(0,ms-cs*10)+39)//40
            if tick>255:raise ValueError(f"Row timing span exceeds 10.2 seconds: {text!r}")
            payload.append(tick)
    dest=Path(destination);dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(f'[ti:{title}]\n'+''.join(f'[{cs//6000:02d}:{cs//100%60:02d}.{cs%100:02d}]{text}\n' for cs,text,_ in adjusted),encoding='utf-8',newline='\n')
    dest.write_bytes(normalize_card_lrc(dest))
    if read_lrc(dest,max_chars=31)!=[(cs,text) for cs,text,_ in adjusted]:raise ValueError("LRC normalization mismatch")
    write_card_font([dest],Path(font_destination))
    bank=bytearray(Path(font_destination).read_bytes());bank.extend(bytes(16384-len(bank)))
    bank[8712:8720]=b'LKT1'+struct.pack('<HBB',len(payload),4,quality)
    bank[9216:9216+len(payload)]=payload
    Path(font_destination).write_bytes(bank)
    return {'cues':len(adjusted),'characters':len(payload),'timing':'KRC' if quality==1 else 'estimated LRC','bytes':dest.stat().st_size}


def main():
    import argparse,tempfile
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path,help='Original KRC or standard LRC')
    parser.add_argument('track',type=int,choices=range(1,17))
    parser.add_argument('output',type=Path)
    parser.add_argument('--base-font',type=Path,required=True,help='Current 262144-byte FONT.BIN; other banks are preserved')
    parser.add_argument('--title',required=True)
    args=parser.parse_args();font=bytearray(args.base_font.read_bytes())
    if len(font)!=262144:raise ValueError('Base FONT.BIN must contain sixteen 16-KiB banks')
    args.output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output) as temporary:
        slot=Path(temporary)/'slot.bin'
        info=write_track(args.source,args.title,args.output/f'SONG{args.track}.LRC',slot)
        start=(args.track-1)*16384;font[start:start+16384]=slot.read_bytes()
    (args.output/'FONT.BIN').write_bytes(font)
    print(f"Prepared SONG{args.track}.LRC and FONT.BIN: {info}")

if __name__=='__main__':main()
