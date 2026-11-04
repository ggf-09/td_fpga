`timescale 1ns/1ps
module test_resume_startup;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,boot_ready=0,record_valid=1,route_ready=0,manual_accepted=0,consumed=0,user_cancel=0;
 reg [3:0] current_track=0,record_track=15;reg [15:0] playable=16'hffff;
 wire hold_audio,route_request,apply_position,ready;wire [3:0] route_target;
 resume_startup dut(.*);
 task reset;
 begin rst_n=0;boot_ready=0;route_ready=0;manual_accepted=0;consumed=0;repeat(3)@(negedge clk);rst_n=1;end
 endtask
 initial begin
  reset();repeat(5)@(negedge clk);if(!hold_audio)$fatal(1,"audio released before card record");
  boot_ready=1;repeat(3)@(negedge clk);if(route_request || !hold_audio)$fatal(1,"route not ready");
  route_ready=1;wait(route_request);@(negedge clk);
  if(route_target!=15)$fatal(1,"global track truncated");
  route_ready=0;manual_accepted=1;@(negedge clk);manual_accepted=0;
  repeat(10)@(negedge clk);if(!hold_audio)$fatal(1,"audio released before page ready");
  current_track=15;route_ready=1;wait(ready);@(negedge clk);
  if(hold_audio || !apply_position)$fatal(1,"restore not armed");
  consumed=1;@(negedge clk);consumed=0;if(apply_position)$fatal(1,"restore repeated");
  reset();record_valid=0;boot_ready=1;wait(ready);if(apply_position)$fatal(1,"blank applied");
  reset();record_valid=1;playable=1;boot_ready=1;wait(ready);if(apply_position)$fatal(1,"missing song applied");
  $display("PASS resume startup: audio hold, song16 cross-page request, route acknowledgement, consume once, blank and missing song fallback");$finish;
 end
 initial begin #10000;$fatal(1,"startup timeout");end
endmodule
