`timescale 1ns/1ps
module test_lyric_panel_controls;
 reg clk=0,rst_n=0,kn=1,kp=1,kv=1;always #5 clk=~clk;
 reg [3:0] sw=0;
 wire [1:0] alpha;wire [2:0] pos;wire [3:0] edit;
 wire paused,seek,back,fwd,clean;wire [4:0] volume;
 wire [2:0] brightness,contrast,bass,mid,treble;
 playback_controls #(.CLOCK_HZ(1000)) dut(
 .clk(clk),.rst_n(rst_n),.key_next_n(kn),.key_pause_n(kp),.key_view_n(kv),
 .thumbnail(1'b0),.volume_switch(sw[0]),.eq_switches(sw[3:1]),
 .next_song(),.previous_song(),.thumb_right(),.thumb_left(),.thumb_confirm(),.thumb_toggle(),.mode_next(),
 .paused(paused),.volume(volume),.brightness(brightness),.contrast(contrast),.volume_mode(),
 .bass(bass),.mid(mid),.treble(treble),.edit_target(edit),
 .seek_backward(back),.seek_forward(fwd),.seek_mode(seek),.transition_pref(),.clean_mode(clean),
 .lyric_alpha(alpha),.lyric_position(pos));
 integer i;
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task combo;input [3:0] n;begin sw=n;tick(80);end endtask
 task down;begin kp=0;tick(30);kp=1;tick(30);end endtask
 task up;begin kv=0;tick(30);kv=1;tick(30);end endtask
 initial begin
  tick(4);rst_n=1;tick(80);
  if(alpha!=1||pos!=7)$fatal(1,"legacy panel defaults changed");
  combo(12);if(edit!=9||seek||clean)$fatal(1,"alpha combo not isolated");
  down();if(alpha!=0)$fatal(1,"alpha down");down();if(alpha!=0)$fatal(1,"alpha underflow");
  for(i=0;i<5;i=i+1)up();if(alpha!=3||pos!=7)$fatal(1,"alpha limit/isolation");
  combo(14);if(edit!=10||seek||clean)$fatal(1,"position combo not isolated");
  for(i=0;i<9;i=i+1)down();if(pos!=0||alpha!=3)$fatal(1,"top clamp/isolation");
  kv=0;tick(2000);kv=1;tick(30);if(pos!=7)$fatal(1,"position hold-repeat/down clamp");
  // A held alpha key must not leak into position editing when remapped.
  combo(12);kp=0;tick(30);combo(14);kp=1;tick(700);
  if(pos!=7)$fatal(1,"held gesture leaked across edit targets");
  combo(7);if(edit!=1||seek)$fatal(1,"legacy triple-switch volume changed");
  combo(0);if(edit!=0||paused||volume!=16||bass!=2||mid!=2||treble!=2||brightness!=0||contrast!=0)
   $fatal(1,"lyric edits leaked to existing controls");
  if(back||fwd)$fatal(1,"lyric edit leaked seek");
  $display("PASS lyric panel controls: default compatibility, ALP4/LOC8 clamps, repeat, held-key remap isolation and preserved settings");$finish;
 end
 initial begin #1000000;$fatal(1,"controls timeout");end
endmodule
