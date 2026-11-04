`timescale 1ns/1ps
// New image/playback switch combinations on playback_controls:
//   0101 = brightness (edit_target 6, KEY3 down / KEY4 up, clamp 0..4)
//   1001 = contrast   (edit_target 7, KEY3 down / KEY4 up, clamp 0..4)
//   0110 = transition preference (edit_target 8, KEY4 = WIPE, KEY3 = FADE)
//   1010 = clean mode (clean_mode output, edit_target 0, no EQ/image edits)
// Held keys and pending single clicks must be cancelled across combination
// boundaries. Original gesture (debounce/long/double/thumbnail) and exact
// SW1+SW2 seek semantics are preserved below.
module test_image_combo_controls;
 reg clk=0,rst_n=0,kn=1,kp=1,kv=1,thumbnail=0;
 reg [3:0] sw=0;
 always #5 clk=~clk;
 wire ns,prev,tr,tl,tc,tt,mn,paused,vm,back,fwd,seek,tpref,clean;
 wire [4:0] volume;
 wire [2:0] bright,contrast,bass,mid,treble;
 wire [3:0] edit;
 playback_controls #(.CLOCK_HZ(1000)) dut(
  .clk(clk),.rst_n(rst_n),.key_next_n(kn),.key_pause_n(kp),.key_view_n(kv),
  .thumbnail(thumbnail),.volume_switch(sw[0]),.eq_switches(sw[3:1]),
  .next_song(ns),.previous_song(prev),.thumb_right(tr),.thumb_left(tl),
  .thumb_confirm(tc),.thumb_toggle(tt),.mode_next(mn),.paused(paused),
  .volume(volume),.brightness(bright),.contrast(contrast),.volume_mode(vm),
  .bass(bass),.mid(mid),.treble(treble),.edit_target(edit),
  .seek_backward(back),.seek_forward(fwd),.seek_mode(seek),
  .transition_pref(tpref),.clean_mode(clean));
 integer nexts=0,prevs=0,modes=0,views=0,backs=0,fwds=0,lefts=0,rights=0,confirms=0;
 always @(posedge clk) begin
  if(ns)nexts=nexts+1;if(prev)prevs=prevs+1;
  if(mn)modes=modes+1;if(tt)views=views+1;
  if(back)backs=backs+1;if(fwd)fwds=fwds+1;
  if(tl)lefts=lefts+1;if(tr)rights=rights+1;if(tc)confirms=confirms+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task click3;begin kp=0;tick(30);kp=1;tick(30);end endtask
 task click4;begin kv=0;tick(30);kv=1;tick(30);end endtask
 task combo;input [3:0] value;begin sw=value;tick(80);end endtask
 task check;
  input condition;
  input [511:0] message;
  begin if(!condition) begin $display("FAIL combo: %0s",message);$fatal(1);end end
 endtask
 integer i,backs_after_seek;
 initial begin
  tick(4);rst_n=1;tick(80);
  check(edit==0 && !clean && !seek && !tpref,"reset exposes no combination");
  check(volume==16 && bright==0 && contrast==0 && bass==2 && mid==2 && treble==2,
        "reset defaults changed");
  // ---- 0101: brightness, 0..4 clamp, KEY4 up / KEY3 down, full isolation ----
  combo(5);check(edit==6 && !clean && !seek && !vm,"0101 must select brightness target 6");
  for(i=0;i<6;i=i+1)click4;
  check(bright==4,"brightness upper clamp");
  check(volume==16 && contrast==0 && bass==2 && mid==2 && treble==2 && !tpref,
        "brightness leaked volume/contrast/EQ/transition");
  check(!paused && modes==0 && views==0,"brightness leaked pause/double-click");
  for(i=0;i<6;i=i+1)click3;
  check(bright==0,"brightness lower clamp");
  click4;click4;check(bright==2,"brightness KEY4 direction wrong");
  // ---- 1001: contrast, 0..4 clamp ----
  combo(9);check(edit==7 && !clean && !seek,"1001 must select contrast target 7");
  for(i=0;i<6;i=i+1)click4;
  check(contrast==4 && bright==2,"contrast clamp or brightness leak");
  for(i=0;i<6;i=i+1)click3;
  check(contrast==0,"contrast lower clamp");
  click4;check(contrast==1,"contrast KEY4 direction wrong");
  check(volume==16 && bass==2 && mid==2 && treble==2 && !paused,"contrast leaked playback state");
  // ---- 0110: transition preference, KEY4 = WIPE / KEY3 = FADE ----
  combo(6);check(edit==8 && !clean && !seek,"0110 must select transition target 8");
  click4;check(tpref==1,"KEY4 must choose WIPE");
  click4;check(tpref==1,"WIPE preference must stick");
  click3;check(tpref==0,"KEY3 must choose FADE");
  click3;check(tpref==0,"FADE preference must stick");
  check(volume==16 && bright==2 && contrast==1 && bass==2 && !paused && modes==0 && views==0,
        "transition editing leaked other state");
  // Lower the volume through SW1 first: normal KEY3/KEY4 must not move it.
  combo(1);check(edit==1 && vm,"SW1 volume edit unavailable");
  click3;click3;click3;click3;check(volume==12,"SW1 volume down failed");
  // ---- 1010: clean mode, normal gestures survive but no EQ/image edits ----
  combo(10);check(clean==1 && edit==0 && !seek,"1010 must raise clean mode with no edit target");
  kp=0;tick(1300);kp=1;tick(30);
  check(volume==12 && !paused,"normal KEY3 long changed volume or pause");
  click4;tick(850);check(volume==12,"normal KEY4 single changed volume");
  kv=0;tick(1300);kv=1;tick(30);check(volume==12,"normal KEY4 long changed volume");
  click3;tick(850);check(paused,"clean mode lost normal pause gesture");
  click3;tick(850);check(!paused,"clean mode lost normal resume gesture");
  check(bass==2 && mid==2 && treble==2 && bright==2 && contrast==1 && !tpref,
        "clean mode adjusted EQ/image/transition");
  check(modes==0 && views==0 && backs==0 && fwds==0,"clean mode leaked mode/seek actions");
  // ---- Cross-combination cancellation ----
  // A key held across a combination change must not act in the new target.
  combo(5);kp=0;tick(30);check(bright==1,"brightness press before crossing missing");
  combo(9);kp=1;tick(600);
  check(contrast==1 && bright==1,"held KEY3 leaked across combination boundary");
  click4;check(contrast==2,"combination keys did not rearm after release");
  // A pending normal single click dies when a combination appears mid-window.
  combo(0);click4;combo(5);tick(700);
  check(volume==12 && bright==1,"pending single click leaked into brightness combination");
  // ---- Exact SW1+SW2 seek semantics preserved ----
  combo(0);click3;tick(850);check(paused,"normal pause unavailable before seek");
  combo(3);check(seek==1 && edit==5 && !vm && !clean,"SW1+SW2 must be the only seek combination");
  click3;click4;tick(600);
  check(backs==1 && fwds==1 && paused && volume==12 && bass==2 && mid==2 && treble==2 &&
        bright==1 && contrast==2 && !tpref && modes==0 && views==0,
        "seek leaked pause/double/volume/EQ/image");
  kp=0;tick(1500);kp=1;tick(600);
  check(backs>2 && fwds==1 && paused,"held seek did not auto-repeat or leaked long gesture");
  backs_after_seek=backs;
  combo(7);check(seek==0 && edit==1,"SW1+SW2+SW3 must not act as seek");
  click3;check(volume==11 && backs==backs_after_seek,"SW1 priority inside 0111 broken");
  click4;check(volume==12,"volume recovery inside 0111 broken");
  // ---- Original gesture semantics preserved ----
  combo(0);
  kn=0;tick(5);kn=1;tick(600);check(nexts==0,"bounce accepted");
  kn=0;tick(60);kn=1;tick(30);check(nexts==1 && !paused,"next missing or pause not cleared");
  kn=0;tick(1300);kn=1;tick(30);check(prevs==1 && nexts==1,"long leaked next");
  click3;tick(100);click3;tick(510);check(modes==1 && !paused,"auto double leaked pause");
  click4;tick(100);click4;tick(850);check(views==1 && volume==12,"view double leaked volume");
  thumbnail=1;
  kn=0;tick(60);kn=1;tick(30);
  kn=0;tick(1300);kn=1;tick(30);
  click4;tick(850);
  check(rights==1 && confirms==1 && lefts==1 && nexts==1 && prevs==1,"thumbnail navigation regression");
  kv=0;tick(1300);kv=1;tick(30);
  check(bright==2 && lefts==1,"thumbnail brightness leaked left");
  kv=0;tick(3100);kv=1;tick(30);
 check(bright==3 && contrast==2,"3.1s hold must be brightness (widened 1.2~6s window)");
 kv=0;tick(6100);kv=1;tick(30);
  check(contrast==3,"thumbnail contrast missing");
  thumbnail=0;
  $display("PASS image combos: 0101 brightness / 1001 contrast clamps and direction, 0110 FADE/WIPE preference, 1010 clean isolation, cross-combination cancellation, preserved seek and gesture semantics");
  $finish;
 end
 initial begin #8000000;$fatal(1,"timeout");end
endmodule
