`timescale 1ns/1ps
module test_file_streamer_start;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,file_start=0;
 reg [31:0] first_cluster=2,file_size=4;
 reg [7:0] sectors_per_cluster=1;
 wire file_busy,file_done,file_valid,sector_req;
 wire [7:0] file_byte,fs_error;
 wire [31:0] file_byte_offset,sector_lba;
 reg sector_busy=0,sector_valid=0,sector_done=0;
 reg [7:0] sector_byte=0;
 reg [8:0] sector_byte_index=0;
 integer n,reads=0,bytes_seen=0;
 reg [31:0] request;
 fat32_file_streamer dut(.clk(clk),.rst_n(rst_n),.file_start(file_start),
  .first_cluster(first_cluster),.file_size(file_size),.sectors_per_cluster(sectors_per_cluster),
  .fat_start_lba(32'd1),.data_start_lba(32'd100),.max_cluster(32'd2),
  .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_byte_offset(file_byte_offset),.fs_error(fs_error),.sector_req(sector_req),.sector_lba(sector_lba),
  .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),
  .sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(8'd0));
 always @(posedge clk)if(file_valid)begin
  if(file_byte!==8'ha0+bytes_seen || file_byte_offset!==bytes_seen)$fatal(1,"data mismatch");
  bytes_seen=bytes_seen+1;
 end
 initial forever begin
  @(negedge clk);
  if(sector_req&&!sector_busy)begin
   sector_busy=1;reads=reads+1;request=sector_lba;
   if(request!=100&&request!=1)$fatal(1,"descriptor snapshot lost: LBA%0d",request);
   @(negedge clk);
   for(n=0;n<512;n=n+1)begin
    sector_valid=1;sector_byte_index=n;sector_byte=0;
    if(request==100)sector_byte=8'ha0+n;
    else if(n>=8&&n<12)sector_byte=n==11?8'h0f:8'hff;
    @(negedge clk);
   end
   sector_valid=0;sector_done=1;@(negedge clk);sector_done=0;sector_busy=0;
  end
 end
 task invalid;
  input [31:0] cluster;
  input [31:0] size;
  input [7:0] spc,expected;
  begin
   @(negedge clk);first_cluster=cluster;file_size=size;sectors_per_cluster=spc;file_start=1;
   @(negedge clk);file_start=0;
   wait(file_done);@(negedge clk);
   if(fs_error!==expected||reads!=0||bytes_seen!=0)$fatal(1,"invalid/empty start mismatch");
   repeat(2)@(negedge clk);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  invalid(0,0,0,0);invalid(0,4,1,8'h24);invalid(1,4,1,8'h24);
  invalid(3,4,1,8'h24);invalid(2,4,0,8'h24);
  first_cluster=2;file_size=4;sectors_per_cluster=1;file_start=1;
  @(negedge clk);file_start=0;first_cluster=99;sectors_per_cluster=128;
  wait(file_done);@(negedge clk);
  if(fs_error!=0||bytes_seen!=4||reads!=2)$fatal(1,"valid boundary start failed");
  $display("PASS file start pipeline: empty priority, low/high invalid clusters, zero geometry, descriptor snapshot, ordered bytes and final FAT");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
