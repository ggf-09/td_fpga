`timescale 1ns/1ps
module test_adjust_bar_overlay;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,frame_start=0,de=1,clean_mode=0,thumbnail=0,transition_pref=0;
 reg [9:0] pixel_x=0,pixel_y=0;
 reg [4:0] volume=16;
 reg [2:0] bass=2,mid=2,treble=2,brightness=0,contrast=0;reg [3:0] edit_target=0;
 reg [1:0] lyric_alpha=1;reg [2:0] lyric_position=7;
 reg [23:0] rgb_in=24'h123456;
 wire [23:0] rgb_out;wire osd_active;
 integer checks=0,f,x,y;
 adjust_bar_overlay dut(.*);
 task check;input condition;input [511:0] message;begin
  if(!condition)begin $display("FAIL adjust bar: %0s",message);$fatal(1);end
  checks=checks+1;
 end endtask
 task frame;begin
  @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
 end endtask
 task pixel;input [9:0] x,y;begin pixel_x=x;pixel_y=y;#1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;frame();
  pixel(200,450);check(!osd_active&&rgb_out==rgb_in,"idle panel is transparent");
  edit_target=1;volume=16;frame();
  pixel(184,446);check(dut.character=="V","volume label is VOL");
  pixel(224,446);check(rgb_out==24'h44ddff,"first of seventeen volume segments lit");
  pixel(416,446);check(rgb_out==24'h44ddff,"volume 16 lights seventeenth segment");
  pixel(426,446);check(rgb_out==24'h44ddff,"volume 16 reaches final segment end");
  pixel(235,446);check(rgb_out==24'h101820,"one-pixel segment gap retained");
  pixel(440,446);check(dut.character=="1","volume 16 numeric tens digit");
  pixel(446,446);check(dut.character=="6","volume 16 numeric ones digit");
  volume=0;frame();pixel(236,446);
  check(rgb_out==24'h101820,"volume zero lights only first segment");
  pixel(440,446);check(dut.character==" ","volume zero tens digit blank");
  pixel(446,446);check(dut.character=="0","volume zero numeric ones digit");
  edit_target=2;bass=4;frame();pixel(184,446);
  check(dut.character=="B","bass label is BAS");
  pixel(388,446);check(rgb_out==24'h44ddff,"fifth bass segment lit");
  pixel(426,446);check(rgb_out==24'h44ddff,"bass 4 reaches final segment end");
  pixel(428,446);check(rgb_out==24'h101820,"five-segment bar ends cleanly");
  pixel(446,446);check(dut.character=="4","bass level numeric digit");
  edit_target=3;mid=0;frame();pixel(184,446);
  check(dut.character=="M","mid label is MID");
  pixel(446,446);check(dut.character=="0","mid level numeric digit");
  edit_target=4;treble=3;frame();pixel(184,446);
  check(dut.character=="T"&&dut.item==4,"treble label and selection");
  pixel(446,446);check(dut.character=="3","treble level numeric digit");
  edit_target=6;brightness=2;frame();pixel(190,446);
  check(dut.character=="R","brightness label is BRT");
  pixel(306,446);check(rgb_out==24'h44ddff,"brightness third segment lit");
  pixel(446,446);check(dut.character=="2","brightness level numeric digit");
  edit_target=7;contrast=1;frame();pixel(184,446);
  check(dut.character=="C","contrast label is CTR");
  pixel(265,446);check(rgb_out==24'h44ddff,"contrast level one has two segments");
  pixel(306,446);check(rgb_out==24'h101820,"contrast third segment remains dark");
  pixel(446,446);check(dut.character=="1","contrast level numeric digit");
  edit_target=8;transition_pref=0;frame();
  pixel(240,446);check(dut.character=="F"&&rgb_out==24'h44ddff,"FADE selected");
  pixel(288,446);check(dut.character=="W"&&rgb_out==24'h708090,"WIPE unselected");
  pixel(240,455);check(rgb_out==24'h44ddff,"FADE underline");
  transition_pref=1;frame();pixel(240,446);
  check(rgb_out==24'h708090,"FADE deselected");
  pixel(288,446);check(rgb_out==24'h44ddff,"WIPE selected");
  pixel(288,455);check(rgb_out==24'h44ddff,"WIPE underline");
  clean_mode=1;pixel(240,446);
  check(!osd_active&&rgb_out==rgb_in,"clean mode suppresses adjustment panel");
  clean_mode=0;edit_target=0;thumbnail=1;brightness=2;frame();
  pixel(184,446);check(!osd_active,"no stale panel without a new normal-mode change");
  brightness=3;frame();pixel(184,446);
  check(osd_active&&dut.item==6,"browser long-press brightness leaves feedback");
  repeat(120)frame();pixel(184,446);
  check(!osd_active&&rgb_out==rgb_in,"temporary browser feedback expires");
  contrast=4;frame();pixel(184,446);
  check(osd_active&&dut.item==7,"browser long-press contrast leaves feedback");
  pixel(100,450);check(!osd_active&&rgb_out==rgb_in,"left outside passes through");
  pixel(464,450);check(!osd_active&&rgb_out==rgb_in,"shortened panel removes old right blank area");
  pixel(500,450);check(!osd_active&&rgb_out==rgb_in,"right outside passes through");
  pixel(200,468);check(!osd_active&&rgb_out==rgb_in,"progress row untouched");
  edit_target=9;lyric_alpha=3;frame();pixel(184,446);
  check(osd_active&&dut.character=="A","alpha label is ALP");
  pixel(426,446);check(rgb_out==24'h44ddff,"alpha maximum fills bar");
  if(dut.num_value!=3)$fatal(1,"alpha index number");
  edit_target=10;lyric_position=7;frame();pixel(184,446);
  check(osd_active&&dut.character=="L","position label is LOC");
  pixel(426,446);check(rgb_out==24'h44ddff,"position maximum fills bar");
  if(dut.num_value!=7)$fatal(1,"position index number");
  edit_target=1;volume=13;contrast=0;frame();
  f=$fopen("adjust_bar_preview.ppm","w");$fwrite(f,"P3\n320 20\n255\n");
  for(y=440;y<460;y=y+1)for(x=160;x<480;x=x+1)begin
   pixel(x,y);$fwrite(f,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
  end
  $fclose(f);
  $display("PASS adjust bar: %0d checks; 17/5-level bars, FADE/WIPE, clean and 120-frame browser feedback",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"adjust bar timeout");end
endmodule
