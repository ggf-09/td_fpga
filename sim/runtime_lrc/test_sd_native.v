`timescale 1ns/1ps
// Card model interacts solely with the SD SPI pins (mode 3).
module test_sd_native;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,sd_sec_read=0,sd_sec_write=0;
 reg [31:0] sd_sec_read_addr=42,sd_sec_write_addr=42;
 reg [7:0] sd_sec_write_data=0;
 wire SD_nCS,SD_DCLK,SD_MOSI,sd_init_done;
 reg SD_MISO=1;
 wire [7:0] sd_sec_read_data;
 wire sd_sec_read_data_valid,sd_sec_read_end,sd_sec_read_error;
 wire sd_sec_write_data_req,sd_sec_write_error,sd_sec_write_end;
 sd_card_top #(.SPI_LOW_SPEED_DIV(3)) dut(.*);
 reg [7:0] memory[0:511];
 reg [7:0] receive=0,outgoing=255;
 reg [47:0] command_frame=0;
 integer phase=0,bits=0,command_left=0,command_number=0,byte_index=0;
 integer cycles=0,read_bytes=0,write_bytes=0,i,t0,read_cycles,write_cycles;
 integer rejected=0,reject_next=0,seen_read_commands=0,seen_write_commands=0;
 integer response_rejected=0;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(sd_sec_read_data_valid)begin
   if(read_bytes>=512 || sd_sec_read_data!==memory[read_bytes])
    $fatal(1,"native read mismatch byte%0d data%h",read_bytes,sd_sec_read_data);
   read_bytes=read_bytes+1;
  end
  if(sd_sec_write_data_req)begin
   sd_sec_write_data<=(write_bytes*13+9)%256;
   write_bytes=write_bytes+1;
  end
 end
 function [7:0] response_byte;
 begin
  case(phase)
   2:response_byte=response_rejected?8'h04:
     (command_number==0||command_number==8||command_number==55)?8'h01:8'h00;
   3:case(byte_index)0,1:response_byte=0;2:response_byte=1;default:response_byte=8'haa;endcase
   4:response_byte=8'hfe;
   5:response_byte=memory[byte_index];
   10:response_byte=8'h05;
   11:response_byte=byte_index<2?8'h00:8'hff;
   default:response_byte=8'hff;
  endcase
 end endfunction
 always @(posedge SD_nCS)begin bits=0;phase=0;SD_MISO=1;end
 always @(negedge SD_DCLK)if(!SD_nCS)begin
  if(bits==0)outgoing=response_byte();
  SD_MISO=outgoing[7-bits];
 end
 always @(posedge SD_DCLK)if(!SD_nCS)begin
  receive={receive[6:0],SD_MOSI};
  if(bits==7)begin
   bits=0;
   case(phase)
    0:if(receive[7:6]==2'b01)begin
      command_number=receive[5:0];command_frame=receive;command_left=5;phase=1;
     end
    1:begin
      command_frame={command_frame[39:0],receive};command_left=command_left-1;
      if(command_left==0)begin
       phase=2;response_rejected=0;
       if(command_number==17 || command_number==24)begin
        if(command_frame[39:8]!=42)$fatal(1,"wrong command sector %h",command_frame);
        if(command_number==17)begin
         seen_read_commands=seen_read_commands+1;
         if(reject_next)begin response_rejected=1;reject_next=0;rejected=rejected+1;end
        end else seen_write_commands=seen_write_commands+1;
       end
      end
     end
    2:begin
      byte_index=0;
      if(response_rejected)phase=0;
      else case(command_number)8:phase=3;17:phase=4;24:phase=7;default:phase=0;endcase
     end
    3:if(byte_index==3)begin phase=0;byte_index=0;end else byte_index=byte_index+1;
    4:begin phase=5;byte_index=0;end
    5:if(byte_index==511)begin phase=6;byte_index=0;end else byte_index=byte_index+1;
    6:if(byte_index==1)begin phase=0;byte_index=0;end else byte_index=byte_index+1;
    7:if(receive==8'hfe)begin phase=8;byte_index=0;end
    8:begin
      if(receive!==((byte_index*13+9)%256))$fatal(1,"native write mismatch %0d data%h",byte_index,receive);
      memory[byte_index]=receive;
      if(byte_index==511)begin phase=9;byte_index=0;end else byte_index=byte_index+1;
     end
    9:if(byte_index==1)begin phase=10;byte_index=0;end else byte_index=byte_index+1;
    10:begin phase=11;byte_index=0;end
    11:if(byte_index==2)begin phase=0;byte_index=0;end else byte_index=byte_index+1;
   endcase
  end else bits=bits+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task read_sector;begin
  tick(4);read_bytes=0;sd_sec_read=1;t0=cycles;
  wait(sd_sec_read_end);@(negedge clk);read_cycles=cycles-t0;sd_sec_read=0;
  if(read_bytes!=512 || sd_sec_read_error)$fatal(1,"native sector read failed");
  tick(5);
 end endtask
 initial begin
  for(i=0;i<512;i=i+1)memory[i]=(i*7+3)%256;
  tick(4);rst=0;wait(sd_init_done);tick(40);
  read_sector();$display("BENCH read512 controller_cycles=%0d clock_ns=20",read_cycles);
  write_bytes=0;sd_sec_write=1;t0=cycles;
  wait(sd_sec_write_end);@(negedge clk);write_cycles=cycles-t0;sd_sec_write=0;
  if(write_bytes!=512 || sd_sec_write_error || seen_write_commands!=1)$fatal(1,"native sector write failed");
  $display("BENCH write512 controller_cycles=%0d clock_ns=20",write_cycles);
  read_sector();reject_next=1;read_sector();
  if(rejected!=1 || seen_read_commands!=4)$fatal(1,"CMD17 retry missing");
  $display("PASS native SD pins: CMD0/8/55/41/16 initialization, CMD17 512-byte reads, CMD24 ordered512 write, accepted token/busy, readback and rejected-command retry");
  $finish;
 end
 initial begin #20000000;$fatal(1,"native SD timeout phase%0d command%0d",phase,command_number);end
endmodule
