`timescale 1ns/1ps
module test_watchdog;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,load_busy=0,streamer_byte_valid=0;
 wire load_abort;wire [31:0] load_timeout_cnt;
 watchdog_fragment dut(.*);
 integer i,expected_count=0,aborts=0,seed=9481;
 reg expected_abort;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(i=0;i<10000;i=i+1)begin
   if(i<1000)begin load_busy=1;streamer_byte_valid=0;end
   else if(i<2000)begin load_busy=1;streamer_byte_valid=(i%33)==32;end
   else begin load_busy=($random(seed)&7)!=0;streamer_byte_valid=($random(seed)&31)==0;end
   expected_abort=load_busy && !streamer_byte_valid && expected_count>31;
   if(!load_busy || streamer_byte_valid || expected_abort)expected_count=0;
   else expected_count=expected_count+1;
   @(posedge clk);#1;
   if(load_abort!==expected_abort || load_timeout_cnt!==expected_count)
    $fatal(1,"watchdog changed behavior cycle=%d expected=%d count=%d",i,expected_count,load_timeout_cnt);
   if(load_abort)aborts=aborts+1;
   @(negedge clk);
  end
  if(aborts<30)$fatal(1,"insufficient timeout coverage");
  $display("PASS production pipelined watchdog: 10000 cycles match original >limit behavior, progress at terminal count, idle reset and repeated timeouts");$finish;
 end
endmodule
