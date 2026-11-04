`timescale 1ns/1ps
module test_checkpoint_bus;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg ck_want=0,ck_read_req=0,arb_sector_req=0;
 reg [31:0] ck_read_lba=777,arb_sector_lba=123;
 reg sd_sec_read_data_valid=0,sd_sec_read_end=0,sd_sec_read_error=0;
 reg [7:0] sd_sec_read_data=0;
 wire ck_owner,arb_sector_busy,arb_sector_valid,arb_sector_done;
 wire [7:0] arb_sector_byte,arb_sector_error,adapter_byte,adapter_error;
 wire [8:0] arb_sector_byte_index,adapter_index;
 wire adapter_busy,adapter_valid,adapter_done,sd_sec_read;
 wire [31:0] sd_sec_read_addr;
 checkpoint_bus_fragment dut(.*);
 integer i;
 task payload;input checkpoint;
 begin
  for(i=0;i<512;i=i+1)begin
   @(negedge clk);sd_sec_read_data_valid=1;sd_sec_read_data=i;
   #1;if(arb_sector_valid===checkpoint || adapter_index!==i[8:0])$fatal(1,"sector ownership/index mismatch");
   if(ck_owner!==checkpoint)$fatal(1,"owner changed inside sector");
  end
  @(negedge clk);sd_sec_read_data_valid=0;sd_sec_read_end=1;
  #1;if(arb_sector_done===checkpoint)$fatal(1,"done delivered to wrong client");
  @(negedge clk);sd_sec_read_end=0;
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  // A normal request was already issued when a checkpoint asks for the bus.
  @(negedge clk);arb_sector_req=1;ck_want=1;
  @(negedge clk);arb_sector_req=0;
  if(ck_owner || !adapter_busy || sd_sec_read_addr!=123)$fatal(1,"checkpoint stole issued normal request");
  payload(0);
  wait(ck_owner);@(negedge clk);
  if(!arb_sector_busy)$fatal(1,"normal clients not stalled");
  // Ownership stays locked throughout a write and its subsequent readback.
  repeat(50)begin @(negedge clk);if(!ck_owner || !arb_sector_busy)$fatal(1,"write lock lost");end
  ck_read_req=1;@(negedge clk);ck_read_req=0;
  if(sd_sec_read_addr!=777 || !adapter_busy)$fatal(1,"checkpoint readback not issued");
  payload(1);
  repeat(3)@(negedge clk);ck_want=0;
  wait(!ck_owner);@(negedge clk);
  if(arb_sector_busy)$fatal(1,"bus not released");
  arb_sector_req=1;@(negedge clk);arb_sector_req=0;
  if(sd_sec_read_addr!=123)$fatal(1,"normal request not resumed");
  payload(0);
  $display("PASS production checkpoint bus: in-flight normal request retained, write/readback lock, 512-byte ownership, normal reads resume");
  $finish;
 end
 initial begin #100000;$fatal(1,"bus test timeout");end
endmodule
