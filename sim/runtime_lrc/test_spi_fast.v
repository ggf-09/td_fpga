`timescale 1ns/1ps
module test_spi_fast;
 reg sys_clk=0;always #10 sys_clk=~sys_clk;
 reg rst=1,CPOL=1,CPHA=1,nCS_ctrl=1,wr_req=0;
 reg [15:0] clk_div=0;
 reg [7:0] data_in=0;
 wire [7:0] data_out;
 wire nCS,DCLK,MOSI,wr_ack;
 reg MISO=0;
 reg active=0;
 reg [7:0] receive=0,reply=0;
 integer edge_count=0,rx_count=0,tx_count=0,acks=0;
 integer mode,div_index,value,checks=0,half_ns;
 time edge_time=0;
 spi_master dut(.*);
 always @(posedge sys_clk)if(wr_ack)acks=acks+1;
 // A pin-level slave, independent of the engine's internal state.
 always @(DCLK)if(active)begin
  if(edge_count>0 && $time-edge_time!=half_ns)
   $fatal(1,"SPI half period %0t expected%0d",$time-edge_time,half_ns);
  edge_time=$time;edge_count=edge_count+1;
  if((CPHA && DCLK==CPOL)||(!CPHA && DCLK!=CPOL))begin
   receive={receive[6:0],MOSI};rx_count=rx_count+1;
  end else if(CPHA)begin
   MISO=reply[7-tx_count];tx_count=tx_count+1;
  end else begin
   tx_count=tx_count+1;
   if(tx_count<8)MISO=reply[7-tx_count];
  end
 end
 task tick;input integer n;begin repeat(n)@(negedge sys_clk);end endtask
 initial begin
  tick(3);rst=0;tick(3);
  for(mode=0;mode<4;mode=mode+1)begin
   CPOL=mode[1];CPHA=mode[0];tick(3);
   for(div_index=0;div_index<4;div_index=div_index+1)begin
    case(div_index)0:clk_div=0;1:clk_div=1;2:clk_div=3;3:clk_div=248;endcase
    half_ns=clk_div==0?20:(clk_div+2)*20;
    for(value=0;value<256;value=value+1)begin
     if(div_index==3 && value>3)value=255;
     tick(2);data_in=value;reply=value^8'hb7;
     edge_count=0;rx_count=0;tx_count=0;receive=0;acks=0;
     MISO=reply[7];active=1;nCS_ctrl=0;wr_req=1;
     wait(wr_ack);@(negedge sys_clk);wr_req=0;active=0;
     if(edge_count!=16 || rx_count!=8 || receive!==data_in || data_out!==reply || nCS!==0)
      $fatal(1,"SPI mode%0d div%0d val%h edges%0d received%h reply%h",mode,clk_div,data_in,edge_count,receive,data_out);
     tick(3);if(acks!=1)$fatal(1,"duplicate ACK");
     nCS_ctrl=1;checks=checks+1;
    end
   end
  end
  $display("PASS SPI pins: %0d independent full-duplex transactions, all4 modes, div0/1/3/248, exact16 edges, 25MHz fast clock at50MHz controller, unchanged slow init timing, one ACK",checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
