`timescale 1ns/1ps
module test_library_neighbor;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,request=0,previous=0;
 reg [3:0] current=0;
 reg [15:0] playable=16'h9001;
 wire busy,done,found;
 wire [3:0] target;
 library_neighbor_finder dut(.*);
 integer n;
 task find;
 input [3:0] from,expected;input backwards,exists;
 begin
  current=from;previous=backwards;request=1;@(negedge clk);request=0;
  wait(done);@(negedge clk);
  if(found!=exists || (exists&&target!=expected))$fatal(1,"neighbor wrong from=%d backwards=%b target=%d",from,backwards,target);
 end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;@(negedge clk);
  find(0,12,0,1);find(12,15,0,1);find(15,0,0,1);
  find(0,15,1,1);find(15,12,1,1);find(12,0,1,1);
  playable=16'h0100;find(8,8,0,1);find(8,8,1,1);
  playable=0;find(8,0,0,0);
  playable=16'hffff;
  for(n=0;n<16;n=n+1)begin find(n,(n+1)%16,0,1);find(n,(n+15)%16,1,1);end
  $display("PASS serial library neighbor: 16 tracks, both directions, sparse/empty/single list and wrap");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
