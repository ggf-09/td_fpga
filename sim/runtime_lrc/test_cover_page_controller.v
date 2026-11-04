`timescale 1ns/1ps
module test_cover_page_controller;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,init_ready=1,reload_request=0,sector_busy=0,cache_done=1,metadata_done=0;
 reg [1:0] requested_page=0,metadata_page=0;
 wire reloading,quiescing,cache_invalidate,catalog_start,page_done;
 wire [1:0] catalog_page,active_page;
 cover_page_controller dut(.*);
 integer n;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  metadata_page=2;metadata_done=1;@(negedge clk);metadata_done=0;
  if(active_page!=2)$fatal(1,"initial scan page not adopted");
  requested_page=3;sector_busy=1;reload_request=1;#1;
  if(!reloading||!quiescing)$fatal(1,"new audio requests not blocked immediately");
  @(negedge clk);reload_request=0;
  repeat(10)begin
   @(negedge clk);if(cache_invalidate||catalog_start||page_done)$fatal(1,"cache touched before inflight sector drained");
  end
  sector_busy=0;wait(cache_invalidate);@(negedge clk);cache_done=0;
  if(catalog_page!=3)$fatal(1,"wrong target page");
  wait(catalog_start);@(negedge clk);
  repeat(4)@(negedge clk);
  if(!reloading||!quiescing||cache_invalidate)$fatal(1,"metadata ownership incorrect");
  metadata_page=3;metadata_done=1;@(negedge clk);metadata_done=0;
  repeat(4)@(negedge clk);
  if(!reloading||quiescing||page_done||active_page!=3)$fatal(1,"cover load ownership incorrect");
  cache_done=1;wait(page_done);@(negedge clk);
  if(reloading)$fatal(1,"SD not released after all covers");
  // A second reload and card re-init must not reuse stale ready handshakes.
  requested_page=0;reload_request=1;@(negedge clk);reload_request=0;
  wait(cache_invalidate);@(negedge clk);init_ready=0;@(negedge clk);
  if(reloading||page_done)$fatal(1,"card removal failed to cancel pending reload");
  $display("PASS cover page controller: inflight-sector drain, reset, metadata ownership, load completion and removal");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
