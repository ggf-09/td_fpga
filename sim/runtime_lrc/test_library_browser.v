`timescale 1ns/1ps
module test_library_browser;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,key_right=0,key_left=0,key_confirm=0,key_mode=0,frame_start=0;
 reg busy=0,ready=1,menu_ready=1;reg [15:0] playable=16'hffff;
 reg [3:0] current_track=0;reg [1:0] cache_page=0;
 wire view_mode,transition_req,transition_select;wire [3:0] focus_track;
 integer i;
 library_browser_controller dut(.*);
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task frame;begin frame_start=1;tick(1);frame_start=0;end endtask
 task right;begin key_right=1;tick(1);key_right=0;tick(20);if(transition_req)$fatal(1,"arrow committed playback");end endtask
 task left;begin key_left=1;tick(1);key_left=0;tick(20);end endtask
 task mode;begin key_mode=1;tick(1);key_mode=0;end endtask
 initial begin
  tick(3);rst_n=1;tick(2);mode();frame();
  if(!transition_req||transition_select||!view_mode||focus_track!=0)$fatal(1,"enter failed");
  tick(3);
  for(i=1;i<=16;i=i+1)begin right();if(focus_track!==i%16)$fatal(1,"global right/page traversal failed");end
  left();if(focus_track!=15)$fatal(1,"reverse wrap 1->16 failed");
  current_track=4;tick(4);if(focus_track!=15)$fatal(1,"autoplay moved browse cursor");
  key_confirm=1;tick(1);key_confirm=0;busy=1;frame();
  if(transition_req)$fatal(1,"busy router lost queued selection");
  busy=0;frame();if(!transition_req||!transition_select||view_mode||focus_track!=15)$fatal(1,"confirm target not latched");
  tick(3);current_track=0;mode();frame();tick(3);
  playable=16'h8101;right();if(focus_track!=8)$fatal(1,"sparse right skip failed");
  left();if(focus_track!=0)$fatal(1,"sparse left skip failed");
  menu_ready=0;cache_page=2;tick(30);if(focus_track!=8)$fatal(1,"missing MENU fallback did not stay in cached page");
  right();if(focus_track!=8)$fatal(1,"singleton fallback failed");
  playable=0;right();if(focus_track!=8||dut.nav_busy)$fatal(1,"empty catalog nav hung");
  // Background-load window (ready=0): navigation and mode toggle stay alive.
  // Any available confirm is accepted: same-page is served at once by the router,
  // cross-page is queued there and fires when the run completes (no swallowed press).
  ready=0;playable=16'hffff;menu_ready=1;cache_page=2;tick(4);
  if(focus_track!=8)$fatal(1,"focus lost entering background window");
  right();if(focus_track!=9)$fatal(1,"navigation blocked during background load");
  mode();frame();if(!transition_req||view_mode)$fatal(1,"browser close blocked during background");
  tick(3);mode();frame();if(!transition_req||!view_mode)$fatal(1,"browser open blocked during background");
  tick(3);if(focus_track!=0)$fatal(1,"reopen did not start from the playing track");
  for(i=0;i<8;i=i+1)right();
  if(focus_track!=8)$fatal(1,"navigation to cached page failed");
  key_confirm=1;tick(1);key_confirm=0;frame();   // focus 8: page 2 == cache page
  if(!transition_req||!transition_select||view_mode)$fatal(1,"same-page confirm refused during background");
  tick(3);mode();frame();tick(3);
  if(!view_mode||focus_track!=0)$fatal(1,"reopen for cross-page confirm failed");
  key_confirm=1;tick(1);key_confirm=0;frame();   // focus 0: page 0 != cache page 2
  if(!transition_req||!transition_select||view_mode)$fatal(1,"cross-page confirm swallowed during background");
  $display("PASS browser: all16/4pages, reverse wrap, sparse/empty/singleton, cursor independent of autoplay, queued confirm, missing-atlas fallback, background-window nav/toggle, same-page confirm served, cross-page confirm queued");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
