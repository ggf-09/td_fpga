"""Create card-resident MENU.BMP: sixteen cover/title cards, four per row.

The FPGA preloads the 640x480 BMP into reserved SDRAM once at boot.
Browsing uses this atlas and never requests sectors from the audio stream.
"""
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw,ImageFont
from prepare_music_card import read_card_title

def wrap_title(draw,title,font,width):
    rows=[];line=''
    for char in title:
        if line and draw.textlength(line+char,font=font)>width:rows.append(line);line=''
        line+=char
    if line:rows.append(line)
    return rows

def build_menu(folder,destination):
    folder=Path(folder);image=Image.new('RGB',(640,480),(12,18,30))
    draw=ImageDraw.Draw(image);font=ImageFont.truetype('C:/Windows/Fonts/simsun.ttc',12)
    number_font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',11)
    titles=[]
    for number in range(1,17):
        x=((number-1)%4)*160;y=((number-1)//4)*120
        path=folder/f'PIC{number}.BMP';lrc=folder/f'SONG{number}.LRC'
        title=read_card_title(lrc) if lrc.exists() else f'SONG {number:02d}'
        titles.append(title)
        draw.rectangle((x+2,y+2,x+157,y+117),fill=(20,29,44))
        if path.exists():
            with Image.open(path) as cover:thumbnail=ImageOps.contain(cover.convert('RGB'),(152,78),Image.Resampling.LANCZOS)
            image.paste(thumbnail,(x+(160-thumbnail.width)//2,y+3))
        rows=wrap_title(draw,title,font,148)
        if len(rows)>3:raise ValueError(f'Track {number} title does not fit three lines')
        for i,row in enumerate(rows):
            width=draw.textlength(row,font=font)
            draw.text((x+(160-width)/2,y+81+i*12),row,font=font,fill=(235,240,250))
        draw.rectangle((x+4,y+4,x+24,y+17),fill=(12,18,30))
        draw.text((x+7,y+4),f'{number:02d}',font=number_font,fill=(170,200,224))
    destination=Path(destination);destination.parent.mkdir(parents=True,exist_ok=True)
    image.save(destination,format='BMP')
    assert destination.stat().st_size==921654
    return titles

def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('card_folder',type=Path);parser.add_argument('output_bmp',type=Path)
    args=parser.parse_args();build_menu(args.card_folder,args.output_bmp)
if __name__=='__main__':main()
