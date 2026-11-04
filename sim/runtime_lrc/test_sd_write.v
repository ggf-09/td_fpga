`timescale 1ns/1ps
module test_sd_write;
 reg sys_clk=0;always #5 sys_clk=~sys_clk;
 reg rst=1,block_write_req=0;reg [7:0] spi_data_out=8'hff;
 wire spi_wr_req;reg spi_wr_ack=0;
 wire block_write_req_ack,block_write_error,block_write_data_rd;
 wire [7:0] spi_data_in;integer mode=0,count=0,received=0;
 reg [7:0] supplied=0;
 sd_card_cmd #(.WRITE_WAIT_LIMIT(64)) dut(
 .sys_clk(sys_clk),.rst(rst),.spi_clk_div(16'd0),.cmd_req(1'b0),.cmd(48'd0),.cmd_r1(8'd0),.cmd_data_len(16'd0),
 .block_read_req(1'b0),.block_write_req(block_write_req),.block_write_data(supplied),
 .block_write_data_rd(block_write_data_rd),.block_write_req_ack(block_write_req_ack),.block_write_error(block_write_error),
 .spi_wr_req(spi_wr_req),.spi_wr_ack(spi_wr_ack),.spi_data_out(spi_data_out),.spi_data_in(spi_data_in));
 always @(posedge sys_clk)if(block_write_data_rd)begin supplied<=count[7:0];count<=count+1;end
 always @(negedge sys_clk)begin
  spi_wr_ack=0;
  if(spi_wr_req)begin
   spi_wr_ack=1;
   if(dut.state==11)begin
    if(spi_data_in!==received[7:0])$fatal(1,"write data mismatch at %d",received);
    received=received+1;
   end
   spi_data_out=8'hff;
   if(dut.state==13)spi_data_out=mode==1?8'h0b:8'h05;
   if(dut.state==14 && mode==2)spi_data_out=0;
  end
 end
 task trial;input integer m;
 begin
  rst=1;block_write_req=0;count=0;received=0;mode=m;
  repeat(3)@(negedge sys_clk);rst=0;
  wait(dut.state==1);@(negedge sys_clk);block_write_req=1;
  wait(block_write_req_ack || block_write_error);@(negedge sys_clk);block_write_req=0;
  if(count!=512 || received!=512)$fatal(1,"not exactly512 bytes");
  if((m==0 && !block_write_req_ack)||(m!=0 && !block_write_error))$fatal(1,"status mismatch mode%d",m);
  repeat(3)@(negedge sys_clk);
 end endtask
 initial begin trial(0);trial(1);trial(2);$display("PASS SD write: 512 ordered bytes, accepted response, rejected response and busy timeout");$finish;end
 initial begin #1000000;$fatal(1,"SD write timeout");end
endmodule
