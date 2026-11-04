`timescale 1ns/1ps
module test_sevenseg_global;
 reg clk=0,sys_rst_n=0;
 always #5 clk=~clk;
 reg [3:0] library_current_track=0,bmp_err_code=0;
 reg [7:0] media_err=0;
 wire [5:0] seg_sel;
 wire [7:0] seg_data;
 sevenseg_top_fragment dut(.*);
 defparam dut.seg_scan_m0.SCAN_COUNT=2;
 reg [3:0] number;
 wire [6:0] expected;
 seg_decoder reference(.bin_data(number),.seg_data(expected));
 integer track,j;
 reg [7:0] ones,tens;
 task check;
  begin
   repeat(8)@(negedge clk);
   for(j=0;j<22;j=j+1)begin
    if(seg_sel==6'b01_1111 && seg_data!==ones)$fatal(1,"ones mismatch song=%0d got=%h want=%h",library_current_track+1,seg_data,ones);
    if(seg_sel==6'b10_1111 && seg_data!==tens)$fatal(1,"tens mismatch song=%0d got=%h want=%h",library_current_track+1,seg_data,tens);
    @(negedge clk);
   end
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);sys_rst_n=1;
  for(track=1;track<=16;track=track+1)begin
   library_current_track=track-1;number=track>=10?track-10:track;#1;
   ones={1'b1,expected};tens=track>=10?8'hf9:8'hff;check;
  end
  bmp_err_code=4'hc;number=4'hc;#1;ones={1'b1,expected};tens=8'hff;check;
  bmp_err_code=0;media_err=8'h63;number=6;#1;ones={1'b1,expected};check;
  bmp_err_code=4'ha;number=4'ha;#1;ones={1'b1,expected};check;
  bmp_err_code=0;media_err=0;number=6;#1;ones={1'b1,expected};tens=8'hf9;check;
  $display("PASS actual top six-digit scan: decimal songs1..16,10/16, error priority and recovery");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
