`timescale 1ns/1ps
module test_checkpoint_cdc;
 reg src_clk=0,dst_clk=0,src_rst_n=0,dst_rst_n=0;
 always #7 src_clk=~src_clk;always #5 dst_clk=~dst_clk;
 reg [15:0] serial=0;
 wire [37:0] source_bundle={serial,~serial,6'h2b};
 wire [37:0] destination_bundle;
 checkpoint_snapshot_cdc dut(.*);
 always @(posedge src_clk)if(src_rst_n)serial<=serial+1'b1;
 integer checked=0;
 always @(negedge dst_clk)if(dst_rst_n && destination_bundle!=0)begin
  if((destination_bundle[37:22]^destination_bundle[21:6])!=16'hffff || destination_bundle[5:0]!=6'h2b)
   $fatal(1,"torn snapshot");
  checked=checked+1;
 end
 initial begin
  repeat(3)@(negedge src_clk);src_rst_n=1;dst_rst_n=1;
  repeat(2000)@(negedge dst_clk);
  src_rst_n=0;dst_rst_n=0;repeat(5)@(negedge src_clk);src_rst_n=1;dst_rst_n=1;
  repeat(2000)@(negedge dst_clk);
  if(checked<3500)$fatal(1,"snapshot did not transfer");
  $display("PASS coherent 38-bit snapshot across asynchronous clocks and reset");$finish;
 end
endmodule
