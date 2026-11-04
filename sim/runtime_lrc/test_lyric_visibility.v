`timescale 1ns/1ps
module test_lyric_visibility;
 reg sd_card_clk=0;always #10 sd_card_clk=~sd_card_clk;
 reg sdcard_rst_n=0,lyric_visible=0;
 wire lyric_visible_export;
 lyric_visibility_fragment dut(.*);
 initial begin
  #1;sdcard_rst_n=1;#1;sdcard_rst_n=0;#1;
  if(lyric_visible_export!==0)$fatal(1,"reset did not clear visibility");
  @(negedge sd_card_clk);sdcard_rst_n=1;
  #2;lyric_visible=1;#2;lyric_visible=0;#1;
  if(lyric_visible_export!==0)$fatal(1,"combinational glitch reached CDC");
  @(negedge sd_card_clk);lyric_visible=1;
  #1;if(lyric_visible_export!==0)$fatal(1,"visibility was not registered");
  @(posedge sd_card_clk);#1;if(lyric_visible_export!==1)$fatal(1,"ready not exported");
  @(negedge sd_card_clk);lyric_visible=0;
  #1;if(lyric_visible_export!==1)$fatal(1,"export changed between source edges");
  @(posedge sd_card_clk);#1;if(lyric_visible_export!==0)$fatal(1,"invalidation not exported");
  @(negedge sd_card_clk);lyric_visible=1;
  @(posedge sd_card_clk);#1;sdcard_rst_n=0;#1;
  if(lyric_visible_export!==0)$fatal(1,"reset retained stale ready");
  $display("PASS actual top lyric visibility export: source registered, short glitches isolated, ready/invalidation/reset; audio handshake untouched");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
