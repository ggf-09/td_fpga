`timescale 1ns/1ps
module test_sd_write_controller;
 reg clk=0;always #5 clk=~clk;reg rst=1;
 wire sd_init_done,sd_sec_read_data_valid,sd_sec_read_end,sd_sec_read_error;
 wire [7:0] sd_sec_read_data;
 reg sd_sec_read=0,sd_sec_write=0;
 reg [31:0] sd_sec_read_addr=0,sd_sec_write_addr=123456;
 reg [7:0] sd_sec_write_data=8'hac;
 wire sd_sec_write_data_req,sd_sec_write_error,sd_sec_write_end;
 wire [15:0] spi_clk_div,cmd_data_len;wire [47:0] cmd;wire [7:0] cmd_r1,block_write_data;
 wire cmd_req,block_read_req,block_write_req;
 reg cmd_req_ack=0,cmd_req_error=0,block_read_valid=0,block_read_req_ack=0,block_read_error=0;
 reg [7:0] block_read_data=0;
 reg block_write_data_rd=0,block_write_error=0,block_write_req_ack=0;
 sd_card_sec_read_write dut(.*);
 task request;input reject;
 begin
  wait(dut.state==17);@(negedge clk);sd_sec_write=1;
  wait(cmd_req);@(negedge clk);
  if(cmd[47:40]!=24 || cmd[39:8]!=123456)$fatal(1,"CMD24 address mismatch");
  if(sd_sec_write_error)$fatal(1,"previous error not cleared");
  sd_sec_write=0;cmd_req_ack=1;cmd_req_error=reject;
  @(negedge clk);cmd_req_ack=0;cmd_req_error=0;
 end endtask
 task completed;input expected;
 begin
  wait(sd_sec_write_end);#1;
  if(sd_sec_write_error!==expected || block_write_req)$fatal(1,"write completion/error mismatch");
  @(negedge clk);@(negedge clk);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  // Card initialization is unchanged; enter its documented post-init state
  // to isolate command rejection, data rejection and transaction recovery.
  force dut.state=17;@(negedge clk);release dut.state;
  request(1);completed(1);
  request(0);wait(block_write_req);@(negedge clk);block_write_error=1;
  @(negedge clk);block_write_error=0;completed(1);
  request(0);wait(block_write_req);@(negedge clk);block_write_data_rd=1;
  #1;if(!sd_sec_write_data_req || block_write_data!=8'hac)$fatal(1,"write byte request not forwarded");
  @(negedge clk);block_write_data_rd=0;block_write_req_ack=1;
  @(negedge clk);block_write_req_ack=0;completed(0);
  $display("PASS SD write controller: CMD24 rejection, block error propagation, error clearing, successful retry transaction and byte handshake");$finish;
 end
 initial begin #100000;$fatal(1,"SD controller timeout");end
endmodule
