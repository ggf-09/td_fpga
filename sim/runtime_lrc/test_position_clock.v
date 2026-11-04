`timescale 1ns/1ps
module test_position_clock;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 reg [31:0] sample_position=0;
 wire [15:0] centiseconds;
 audio_position_clock dut(.*);
 integer i;
 reg [31:0] expected;
 task check;input [31:0] value;
 begin
  @(negedge clk);sample_position=value;repeat(70)@(negedge clk);
  expected=value/480;if(expected>65535)expected=65535;
  if(centiseconds!==expected[15:0])$fatal(1,"position %0d -> %0d expected %0d",value,centiseconds,expected);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  check(0);check(479);check(480);check(481);check(480000);check(4800000);
  check(960);check(0);check(32'hffffffff);check(31456800);check(31457280);
  for(i=0;i<100;i=i+1)check($random);
  $display("PASS source position: /480 boundaries, arbitrary forwards/backwards seeks, saturation and 100 random absolute positions");$finish;
 end
endmodule
