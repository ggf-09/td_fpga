`timescale 1ns/1ps
`include "global_def.v"
module test_refresh;
  reg clk=0; always #4 clk=~clk;
  reg rst=1;
  reg ack=0;
  wire done,req;
  integer cycles=0,last_req=0,pulses=0;
  reg req_q=0;
  sdr_init_ref dut(
    .Sdr_clk(clk),.Rst(rst),.Sdr_init_req(1'b0),.Sdr_init_mode(4'd7),
    .Sdr_init_done(done),.App_ref_req(1'b0),.Sdr_ref_req(req),
    .Sdr_ref_ack(ack),.Sdr_rw_vld(1'b0),.Sdr_init_ref_vld(),
    .Sdr_init_ref_ras(),.Sdr_init_ref_cas(),.Sdr_init_ref_we(),
    .Sdr_init_ref_ba(),.Sdr_init_ref_addr());
  always @(posedge clk) begin
    ack<=req;
    if(!rst && done) begin
      cycles=cycles+1;
      if(req) begin
        if(req_q) $fatal(1,"refresh request is not a single pulse");
        if(pulses!=0 && cycles-last_req!=3906)
          $fatal(1,"wrong refresh interval: %0d",cycles-last_req);
        last_req=cycles;
        pulses=pulses+1;
      end
      req_q=req;
    end
  end
  initial begin
    $display("REFRESH_TERMINAL=%0d CLK_PERIOD=%0d",`SELF_REFRESH_INTERVAL,`SDR_CLK_PERIOD);
    repeat(8) @(negedge clk); rst=0;
    wait(done===1'b1);
    repeat(20000) @(negedge clk);
    if(pulses<5) $fatal(1,"periodic refresh missing: %0d pulses",pulses);
    $display("PASS periodic SDRAM refresh: %0d pulses, 3906 cycles apart",pulses);
    $finish;
  end
  initial begin #2000000; $fatal(1,"init/refresh timeout"); end
endmodule
