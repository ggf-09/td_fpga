`timescale 1ns/1ps
// video_fade_transition manual transition preference. A manual next event
// still runs the full fade-out -> black dwell -> recover sequence; only the
// recovery style depends on manual_wipe: 0 = alpha FADE-in, 1 = WIPE reveal.
// The automatic slideshow path (index_commit in S_IDLE) is always a WIPE and
// ignores manual_wipe. The switch request is only released at the fully
// black frame (next_event_out pulses during S_HOLD), and events arriving
// while a transition runs are dropped.
module test_fade_manual_wipe;
 reg ctrl_clk=0,pix_clk=0;
 always #5 ctrl_clk=~ctrl_clk;
 always #20 pix_clk=~pix_clk;
 reg ctrl_rst_n=0,pix_rst_n=0;
 reg next_event_in=0,player_active=1,frame_start=0,index_commit=0,auto_commit_mask=0,manual_wipe=0;
 reg [1:0] active_index=0;
 wire next_event_out,fade_busy,fade_active,wipe_active;
 wire [7:0] alpha_out;
 wire [4:0] ramp_out;
 wire [1:0] transition_kind;
 video_fade_transition #(.FADE_FRAMES(4)) dut(
  .ctrl_clk(ctrl_clk),.ctrl_rst_n(ctrl_rst_n),
  .next_event_in(next_event_in),.next_event_out(next_event_out),.fade_busy(fade_busy),
  .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
  .player_active(player_active),.frame_start(frame_start),.index_commit(index_commit),
  .auto_commit_mask(auto_commit_mask),.active_index(active_index),
  .alpha_out(alpha_out),.fade_active(fade_active),
  .wipe_active(wipe_active),.ramp_out(ramp_out),
  .transition_kind(transition_kind),.manual_wipe(manual_wipe));
 integer pulses=0;
 always @(posedge next_event_out) pulses=pulses+1;
 task c_tick;input integer n;begin repeat(n)@(negedge ctrl_clk);end endtask
 task p_tick;input integer n;begin repeat(n)@(negedge pix_clk);end endtask
 task check;
  input condition;
  input [511:0] message;
  begin if(!condition) begin $display("FAIL fade: %0s",message);$fatal(1);end end
 endtask
 task request;begin @(negedge ctrl_clk);next_event_in=1;@(negedge ctrl_clk);next_event_in=0;end endtask
 task commit;begin @(negedge pix_clk);index_commit=1;@(negedge pix_clk);index_commit=0;end endtask
 // One frame_start pulse; alpha/ramp step exactly once per pulse.
 task frame;begin @(negedge pix_clk);frame_start=1;@(negedge pix_clk);frame_start=0;#1;end endtask
 initial begin
  p_tick(3);c_tick(2);ctrl_rst_n=1;pix_rst_n=1;p_tick(2);c_tick(2);
  check(alpha_out==255 && !fade_active && !fade_busy && !next_event_out && !wipe_active &&
        ramp_out==0 && transition_kind==0,"idle state wrong");
  // ---- Manual FADE recovery (manual_wipe=0) ----
  request();
  wait(fade_active);#1;
  check(alpha_out==255 && !wipe_active,"fade-out must start at full brightness");
  c_tick(4);check(fade_busy,"control side did not observe busy");
  request(); // dropped: a transition is already running
  frame();check(alpha_out==192,"first fade-out step wrong");
  frame();check(alpha_out==128,"second fade-out step wrong");
  frame();check(alpha_out==64,"third fade-out step wrong");
  frame();check(alpha_out==0 && fade_active,"ramp zero frame must be black");
  frame();check(alpha_out==0 && fade_active,"black dwell not reached");
  wait(next_event_out);#1;
  check(alpha_out==0,"switch request released before fully black frame");
  check(fade_busy,"busy dropped during black dwell");
  p_tick(2);
  check(pulses==1,"dropped event produced a second switch request");
  commit();p_tick(1);#1;
  check(fade_active && !wipe_active,"manual_wipe=0 must recover with FADE not WIPE");
  check(alpha_out==0,"fade-in must start from black");
  frame();check(alpha_out==64 && !wipe_active,"fade-in first step wrong");
  frame();check(alpha_out==128,"fade-in second step wrong");
  frame();check(alpha_out==192,"fade-in third step wrong");
  frame();check(alpha_out==255 && !fade_active,"fade-in did not complete to idle");
  c_tick(4);check(!fade_busy,"busy stuck after manual fade");
  // ---- Manual WIPE recovery (manual_wipe=1) ----
  manual_wipe=1;
  request();
  wait(fade_active);#1;
  frame();frame();frame();
  frame();check(alpha_out==0,"ramp zero frame must be black for wipe run");
  frame();check(alpha_out==0,"black dwell not reached for wipe run");
  wait(next_event_out);#1;
  check(alpha_out==0,"wipe switch request released before black");
  check(pulses==2,"second manual run lost its switch request");
  commit();p_tick(1);#1;
  check(fade_active && wipe_active,"manual_wipe=1 must recover with WIPE");
  check(alpha_out==255,"wipe recovery must not darken the frame");
  check(ramp_out==0,"wipe reveal must start at column zero");
  frame();check(wipe_active && ramp_out==1 && alpha_out==255,"wipe ramp step 1 wrong");
  frame();check(wipe_active && ramp_out==2,"wipe ramp step 2 wrong");
  frame();check(wipe_active && ramp_out==3,"wipe ramp step 3 wrong");
  frame();check(!fade_active && !wipe_active && alpha_out==255,"wipe did not complete to idle");
  c_tick(4);check(!fade_busy,"busy stuck after manual wipe");
  // ---- Automatic slideshow path is always a WIPE ----
  manual_wipe=0;active_index=2;
  commit();p_tick(1);#1;
  check(fade_active && wipe_active,"automatic commit must recover with WIPE");
  check(transition_kind==2,"automatic wipe must expose the committed index");
  check(alpha_out==255,"automatic wipe must not darken the frame");
  frame();frame();frame();
  frame();check(!fade_active,"automatic wipe did not finish");
  c_tick(4);
  check(pulses==2,"automatic wipe must not issue a switch request");
  // auto_commit_mask suppresses the idle automatic wipe.
  auto_commit_mask=1;
  commit();p_tick(2);#1;
  check(!fade_active && !wipe_active,"masked automatic commit still wiped");
  auto_commit_mask=0;
  // An inactive player ignores manual requests entirely.
  player_active=0;
  request();p_tick(3);#1;
  check(!fade_active && pulses==2,"inactive player still ran a transition");
  player_active=1;
  $display("PASS fade manual wipe: S_HOLD->S_IN FADE vs WIPE by manual_wipe, automatic path stays WIPE with committed index, black-frame handshake, busy/event-drop, mask and inactive gating");
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
