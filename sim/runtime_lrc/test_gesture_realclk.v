`timescale 1ns/1ps
// Real 100 MHz counter budgets: a 0.8 s double-click window needs 27 bits,
// and the 6 s very-long threshold needs 30 bits. Low-clock gesture tests
// cannot expose truncation at these thresholds.
module test_gesture_realclk;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,key_next_n=1,key_pause_n=1,key_view_n=1,thumbnail=0;
 reg volume_switch=0;reg [2:0] eq_switches=0;
 wire mode_next,thumb_toggle,paused;
 wire [4:0] volume;wire [2:0] brightness,contrast;
 playback_controls #(.CLOCK_HZ(100000000)) dut(
  .clk(clk),.rst_n(rst_n),.key_next_n(key_next_n),.key_pause_n(key_pause_n),
  .key_view_n(key_view_n),.thumbnail(thumbnail),.volume_switch(volume_switch),
  .eq_switches(eq_switches),.next_song(),.previous_song(),.thumb_right(),
  .thumb_left(),.thumb_confirm(),.thumb_toggle(thumb_toggle),.mode_next(mode_next),
  .paused(paused),.volume(volume),.brightness(brightness),.contrast(contrast),
  .volume_mode(),.bass(),.mid(),.treble(),.edit_target(),.seek_backward(),
  .seek_forward(),.seek_mode(),.transition_pref(),.clean_mode());
 integer modes=0,toggles=0;
 always @(posedge clk)begin
  if(mode_next)modes=modes+1;
  if(thumb_toggle)toggles=toggles+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task check;
  input condition;input [511:0] message;
  begin if(!condition)begin $display("FAIL realclk: %0s",message);$fatal(1);end end
 endtask
 task press34;
  begin
   key_pause_n=0;key_view_n=0;tick(3000000);
   key_pause_n=1;key_view_n=1;tick(2500000);
  end
 endtask
 initial begin
  tick(4);rst_n=1;tick(2100000); // DB=2M: wait for normal keys to arm.
  check($bits(dut.p.pending)>=27,"double-click pending counter is too narrow");
  check($bits(dut.v.held)>=30,"very-long held counter is too narrow");
  // Debounced releases are about 175 ms apart. The old truncated window was
  // only 128.9 ms, so this is a real human double-click regression.
  press34();tick(12000000);press34();tick(10);
  check(modes==1 && toggles==1,"100 MHz KEY3/KEY4 double-click was not recognized");
  check(!paused && volume==16,"double-click leaked pause or volume");
  // Reach the 6 s threshold without simulating 600M cycles. Keep the key
  // pressed while depositing the boundary count, then use the real release
  // debounce and gesture path to verify thumbnail contrast, not brightness.
  thumbnail=1;key_view_n=0;tick(3000000);
  dut.v.held=30'd600000000;key_view_n=1;tick(2500000);
  check(contrast==1 && brightness==0,"6 s threshold did not reach thumbnail contrast");
  check(modes==1 && toggles==1 && volume==16,"very-long press leaked another action");
  $display("PASS real 100 MHz gestures: 27-bit double window, 30-bit very-long threshold, KEY3/KEY4 double actions and thumbnail contrast");
  $finish;
 end
 initial begin #500000000;$fatal(1,"realclk timeout");end
endmodule
