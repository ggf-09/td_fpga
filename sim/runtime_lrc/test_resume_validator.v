`timescale 1ns/1ps
module test_resume_validator;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,check_req=0;
 reg [31:0] actual_size=4000044,actual_cluster=30,saved_size=4000044,saved_cluster=30,saved_frame=480123;
 wire ready,valid;wire [31:0] start_offset;
 resume_file_validator dut(.*);
 task check;input expected;
 begin
  @(negedge clk);check_req=0;@(negedge clk);check_req=1;
  repeat(2)begin @(negedge clk);if(ready)$fatal(1,"validator early ready");end
  wait(ready);@(negedge clk);
  if(valid!==expected)$fatal(1,"validator mismatch frame=%d size=%d",saved_frame,actual_size);
  if(expected && start_offset!=44+saved_frame*4)$fatal(1,"offset mismatch");
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  check(1);saved_frame=999999;check(1);saved_frame=1000000;check(0);
  saved_frame=32'hffffffff;check(0);saved_frame=0;check(1);
  saved_size=1000;check(0);saved_size=4000044;saved_cluster=31;check(0);saved_cluster=30;
  actual_size=44;saved_size=44;check(0);actual_size=43;saved_size=43;check(0);
  actual_size=48;saved_size=48;saved_frame=0;check(1);saved_frame=1;check(0);
  actual_size=32'hffffffff;saved_size=32'hffffffff;saved_frame=1073741811;check(1);
  saved_frame=1073741812;check(0);
  @(negedge clk);check_req=0;@(negedge clk);if(ready || valid)$fatal(1,"cancel did not clear validation");
  $display("PASS staged resume validator: matching descriptors, changed file rejection, frame bounds, short files, 4GB boundary, byte offset and cancellation");$finish;
 end
 initial begin #100000;$fatal(1,"validator timeout");end
endmodule
