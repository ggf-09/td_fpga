`timescale 1ns/1ps

// Compact adjustment feedback placed after the library browser overlay.
// Values and panel selection change only at frame boundaries. The normal
// browser long-press brightness/contrast gestures leave a 120-frame hint.
module adjust_bar_overlay(
 input wire clk,rst_n,frame_start,
 input wire de,clean_mode,thumbnail,transition_pref,
 input wire [9:0] pixel_x,pixel_y,
 input wire [4:0] volume,
 input wire [2:0] bass,mid,treble,brightness,contrast,
 input wire [3:0] edit_target,
 input wire [1:0] lyric_alpha,input wire [2:0] lyric_position,
 input wire [23:0] rgb_in,
 output reg [23:0] rgb_out,
 output wire osd_active
);
 reg [3:0] edit_q,flash_item;
 reg [4:0] volume_q;
 reg [2:0] bass_q,mid_q,treble_q,brightness_q,contrast_q;
 reg transition_q;
 reg [1:0] lyric_alpha_q;reg [2:0] lyric_position_q;
 reg [6:0] flash_frames;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   edit_q<=0;flash_item<=6;volume_q<=16;bass_q<=2;mid_q<=2;treble_q<=2;
   brightness_q<=0;contrast_q<=0;transition_q<=0;flash_frames<=0;lyric_alpha_q<=1;lyric_position_q<=7;
  end else if(frame_start) begin
   edit_q<=edit_target;volume_q<=volume;bass_q<=bass;mid_q<=mid;
   treble_q<=treble;brightness_q<=brightness;contrast_q<=contrast;
   transition_q<=transition_pref;lyric_alpha_q<=lyric_alpha;lyric_position_q<=lyric_position;
   if(flash_frames!=0)flash_frames<=flash_frames-1'b1;
   if(thumbnail&&edit_target==0&&brightness!=brightness_q)begin
    flash_item<=6;flash_frames<=120;
   end else if(thumbnail&&edit_target==0&&contrast!=contrast_q)begin
    flash_item<=7;flash_frames<=120;
   end
  end
 end

 wire edit_visible=edit_q==1||edit_q==2||edit_q==3||edit_q==4||
                   edit_q==6||edit_q==7||edit_q==8||edit_q==9||edit_q==10;
 wire [3:0] item=edit_visible?edit_q:flash_item;
 wire show_panel=!clean_mode&&(edit_visible||flash_frames!=0);
 wire in_panel=de&&show_panel&&pixel_x>=160&&pixel_x<464&&
               pixel_y>=440&&pixel_y<460;
 wire border=pixel_x==160||pixel_x==463||pixel_y==440||pixel_y==459;
 wire [23:0] accent=24'h44ddff;

 reg [7:0] character;
 reg [2:0] glyph_x;
 reg [1:0] label_char;
 reg [2:0] option_char;
 reg option_wipe;
 wire label_area=pixel_y>=446&&pixel_y<453&&pixel_x>=184&&pixel_x<202;
 wire fade_area=pixel_y>=446&&pixel_y<453&&pixel_x>=240&&pixel_x<264;
 wire wipe_area=pixel_y>=446&&pixel_y<453&&pixel_x>=288&&pixel_x<312;
 wire [9:0] label_rel=pixel_x-10'd184;
 wire [9:0] fade_rel=pixel_x-10'd240;
 wire [9:0] wipe_rel=pixel_x-10'd288;
 // 面板右侧数字档位：VOL显示0..16两位十进制，其余调节项显示0..4一位。
 // 数字放在条形区域之后，所有项目共用同一末端，避免最高档仍留大段灰底。
 wire [2:0] level_value=item==2?bass_q:item==3?mid_q:
                        item==4?treble_q:item==6?brightness_q:item==9?{1'b0,lyric_alpha_q}:item==10?lyric_position_q:contrast_q;
 wire [4:0] num_value=item==1?volume_q:{2'b00,level_value};
 wire num_tens=num_value>=5'd10;
 wire [3:0] num_ones=num_value-(num_tens?5'd10:5'd0);
 wire num_area=item!=8&&pixel_y>=446&&pixel_y<453&&pixel_x>=440&&pixel_x<452;
 wire [9:0] num_rel=pixel_x-10'd440;
 wire num_second=num_rel>=6;
 always @* begin
  character=" ";glyph_x=0;label_char=0;option_char=0;option_wipe=0;
  if(label_area)begin
   label_char=label_rel>=12?2:label_rel>=6?1:0;
   glyph_x=label_rel-(label_char==2?12:label_char==1?6:0);
   case(item)
    1:case(label_char)0:character="V";1:character="O";2:character="L";endcase
    2:case(label_char)0:character="B";1:character="A";2:character="S";endcase
    3:case(label_char)0:character="M";1:character="I";2:character="D";endcase
    4:case(label_char)0:character="T";1:character="R";2:character="B";endcase
    6:case(label_char)0:character="B";1:character="R";2:character="T";endcase
    7:case(label_char)0:character="C";1:character="T";2:character="R";endcase
    8:case(label_char)0:character="T";1:character="R";2:character="N";endcase
    9:case(label_char)0:character="A";1:character="L";2:character="P";endcase
    10:case(label_char)0:character="L";1:character="O";2:character="C";endcase
    default:character=" ";
   endcase
  end else if(num_area)begin
   glyph_x=num_rel-(num_second?6:0);
   character=num_second?("0"+num_ones):(num_tens?"1":" ");
  end else if(item==8&&(fade_area||wipe_area))begin
   option_wipe=wipe_area;
   option_char=option_wipe?(wipe_rel>=18?3:wipe_rel>=12?2:wipe_rel>=6?1:0):
                           (fade_rel>=18?3:fade_rel>=12?2:fade_rel>=6?1:0);
   glyph_x=(option_wipe?wipe_rel:fade_rel)-
           (option_char==3?18:option_char==2?12:option_char==1?6:0);
   if(option_wipe)case(option_char)
    0:character="W";1:character="I";2:character="P";3:character="E";
   endcase
   else case(option_char)
    0:character="F";1:character="A";2:character="D";3:character="E";
   endcase
  end
 end

 function [34:0] glyph;
  input [7:0] c;
  begin case(c)
   "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
   "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
   "C":glyph=35'b01110_10001_10000_10000_10000_10001_01110;
   "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
   "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
   "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
   "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
   "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
   "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
   "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
   "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
   "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
   "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
   "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
   "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
   "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
   "W":glyph=35'b10001_10001_10001_10101_10101_10101_01010;
   "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
   "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
   "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
   "3":glyph=35'b11111_00010_00100_00010_00001_10001_01110;
   "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
   "5":glyph=35'b11111_10000_11110_00001_00001_10001_01110;
   "6":glyph=35'b00110_01000_10000_11110_10001_10001_01110;
   "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
   "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
   "9":glyph=35'b01110_10001_10001_01111_00001_00010_01100;
   default:glyph=0;
  endcase end
 endfunction
 wire [34:0] glyph_bits=glyph(character);
 reg [4:0] glyph_row;
 always @* case(pixel_y-10'd446)
  0:glyph_row=glyph_bits[34:30];1:glyph_row=glyph_bits[29:25];
  2:glyph_row=glyph_bits[24:20];3:glyph_row=glyph_bits[19:15];
  4:glyph_row=glyph_bits[14:10];5:glyph_row=glyph_bits[9:5];
  6:glyph_row=glyph_bits[4:0];default:glyph_row=0;
 endcase
 wire text_hit=(label_area||num_area||(item==8&&(fade_area||wipe_area)))&&
               glyph_x<5&&glyph_row[4-glyph_x];
 wire [23:0] text_color=item!=8?accent:
                        option_wipe?(transition_q?accent:24'h708090):
                                    (!transition_q?accent:24'h708090);

 // 统一条形区域 x224..428（205像素）：VOL为17段×12，其他档位为5段×41。
 // 两种条的最高档都在x428前结束，右侧紧接着显示数字，不再留下长灰底。
 wire bar_row=pixel_y>=446&&pixel_y<454;
 wire [9:0] bar_rel=pixel_x-10'd224;
 wire [8:0] volume_count={4'd0,volume_q}+1'b1;
 wire [8:0] volume_limit=(volume_count<<3)+(volume_count<<2);
 wire [7:0] level_count={5'd0,level_value}+1'b1;
 wire [7:0] level_limit=(level_count<<5)+(level_count<<3)+level_count;
 wire volume_gap=bar_rel==10'd11||bar_rel==10'd23||bar_rel==10'd35||
                 bar_rel==10'd47||bar_rel==10'd59||bar_rel==10'd71||
                 bar_rel==10'd83||bar_rel==10'd95||bar_rel==10'd107||
                 bar_rel==10'd119||bar_rel==10'd131||bar_rel==10'd143||
                 bar_rel==10'd155||bar_rel==10'd167||bar_rel==10'd179||
                 bar_rel==10'd191;
 wire level_gap=bar_rel==10'd40||bar_rel==10'd81||bar_rel==10'd122||
                bar_rel==10'd163||bar_rel==10'd204;
 wire volume_bar=item==1&&bar_row&&pixel_x>=224&&pixel_x<429&&
                  bar_rel<volume_limit&&!volume_gap;
 wire level_bar=item!=1&&item<8&&bar_row&&pixel_x>=224&&pixel_x<429&&
                bar_rel<level_limit&&!level_gap;
 wire [8:0] lyric_level_count={6'd0,level_value}+1'b1;
 wire [8:0] alpha_limit=(lyric_level_count<<5)+(lyric_level_count<<4)+(lyric_level_count<<1)+lyric_level_count;
 wire [8:0] position_limit=(lyric_level_count<<4)+(lyric_level_count<<3)+lyric_level_count;
 wire [8:0] lyric_limit=(item==9&&level_value==3 || item==10&&level_value==7)?9'd205:
                         item==9?alpha_limit:position_limit;
 wire lyric_bar=(item==9||item==10)&&bar_row&&pixel_x>=224&&pixel_x<429&&bar_rel<lyric_limit;
 wire fade_underline=item==8&&pixel_y>=455&&pixel_y<457&&
                     pixel_x>=240&&pixel_x<264&&!transition_q;
 wire wipe_underline=item==8&&pixel_y>=455&&pixel_y<457&&
                     pixel_x>=288&&pixel_x<312&&transition_q;
 assign osd_active=in_panel;
 always @* begin
  rgb_out=rgb_in;
  if(in_panel)begin
   rgb_out=border?24'h304050:24'h101820;
   if(volume_bar||level_bar||lyric_bar)rgb_out=accent;
   if(text_hit)rgb_out=text_color;
   if(fade_underline||wipe_underline)rgb_out=accent;
  end
 end
endmodule
