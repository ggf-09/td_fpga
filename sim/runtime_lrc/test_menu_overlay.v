`timescale 1ns/1ps
module test_menu_overlay;
 reg enable=0,de=1,menu_ready=1,menu_card=0,paused=0,stopped=0;
 reg [9:0] pixel_x=0,pixel_y=0;reg [1:0] page=3;reg [3:0] focus_track=15,playing_track=13;
 reg [23:0] rgb_in=24'h213456,clean_rgb=0;
 wire [23:0] rgb_out;
 reg [23:0] atlas[0:307199];
 integer x,y,source_x,source_y,tile,lx,ly,f,green=0,text=0,tp;
 library_browser_overlay dut(.*);
 // Footer strip (y 256..271, one 16px cell per character column) carries the
 // card-state annotation: MENU PRE / FPGA 640X480 TO 160X120 / ADD MENU.BMP.
 task footer_char;
  input integer col;
  input [7:0] want;
  begin
   pixel_x=16+col*16;pixel_y=260;#1;
   if(dut.character!==want)$fatal(1,"footer column %0d shows %0s",col,dut.character);
  end
 endtask
 task footer_pixels;
  input [23:0] color;
  input integer min_count;
  begin
   tp=0;
   for(y=256;y<272;y=y+1)for(x=16;x<400;x=x+1)begin
    pixel_x=x;pixel_y=y;#1;
    if(rgb_out==color)tp=tp+1;
   end
   if(tp<min_count)$fatal(1,"footer annotation lost text pixels: %0d",tp);
  end
 endtask
 initial begin
  $readmemh("menu_atlas.hex",atlas);#2;
  if(rgb_out!==rgb_in)$fatal(1,"normal mode changed pixels");enable=1;
  f=$fopen("browser_preview.rgb","wb");
  for(y=0;y<288;y=y+1)for(x=0;x<640;x=x+1)begin
   pixel_x=x;pixel_y=y;clean_rgb=0;
   if(x<320&&y<240)begin
    lx=x%160;ly=y%120;tile=(y>=120?2:0)+(x>=160?1:0);
    source_x=tile*160+lx;source_y=page*120+ly;
    clean_rgb=atlas[source_y*640+source_x];
    if(tile==focus_track%4&&(lx<2||ly<2||lx>=158||ly>=118))clean_rgb=24'hffe000;
   end
   #1;
   if(rgb_out==24'h20e090)green=green+1;if(rgb_out==24'hd8e6fa)text=text+1;
   $fwrite(f,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
  end
  $fclose(f);
  if(green<20||text<100)$fatal(1,"missing playing marker/sidebar text");
  pixel_y=260;pixel_x=540;#1;if(dut.character!=32)$fatal(1,"footer text repeated after column31");
  pixel_y=350;pixel_x=100;#1;if(rgb_out!==rgb_in)$fatal(1,"browser overwrote scrolling lyric area");
  pixel_y=432;#1;if(rgb_out!==rgb_in)$fatal(1,"browser overwrote spectrum");
  // Card already present: MENU PRE invitation in the ready (blue) color.
  footer_char(0,"M");footer_char(1,"E");footer_char(2,"N");footer_char(3,"U");
  footer_char(4,32);footer_char(5,"P");footer_char(6,"R");footer_char(7,"E");
  footer_pixels(24'hd8e6fa,100);
  // Menu card found on SD but browser not ready: FPGA 640X480 TO 160X120 in amber.
  menu_ready=0;menu_card=1;#1;
  footer_char(0,"F");footer_char(1,"P");footer_char(2,"G");footer_char(3,"A");
  footer_char(4,32);footer_char(5,"6");footer_char(6,"4");footer_char(7,"0");
  footer_char(8,"X");footer_char(9,"4");footer_char(10,"8");footer_char(11,"0");
  footer_char(12,32);footer_char(13,"T");footer_char(14,"O");footer_char(15,32);
  footer_char(16,"1");footer_char(17,"6");footer_char(18,"0");footer_char(19,"X");
  footer_char(20,"1");footer_char(21,"2");footer_char(22,"0");footer_char(23,32);
  footer_pixels(24'hffcc60,300);
  // No card at all: ADD MENU.BMP instruction, also amber.
  menu_card=0;#1;
  footer_char(0,"A");footer_char(1,"D");footer_char(2,"D");footer_char(3,32);
  footer_char(4,"M");footer_char(5,"E");footer_char(6,"N");footer_char(7,"U");
  footer_char(8,".");footer_char(9,"B");footer_char(10,"M");footer_char(11,"P");
  footer_char(12,32);
  footer_pixels(24'hffcc60,150);
  menu_ready=1;#1;
  $display("PASS browser pixels: actual four covers/titles, selected16, playing14, page4, instructions, MENU PRE / FPGA 640X480 TO 160X120 / ADD MENU.BMP footer annotations, lyric/spectrum and full-screen passthrough");$finish;
 end
endmodule
