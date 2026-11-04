`timescale 1ns/1ps
module test_range_stream;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,file_start=0,file_partial=1;
 reg [31:0] start_offset=0,file_size=5000;
 reg [7:0] sectors_per_cluster=2;
 wire file_busy,file_done,file_valid,sector_req;
 wire [7:0] file_byte,fs_error;
 wire [31:0] file_byte_offset,sector_lba;
 reg sector_busy=0,sector_valid=0,sector_done=0;
 reg [7:0] sector_byte=0,sector_error=0;
 reg [8:0] sector_byte_index=0;
 reg [31:0] max_cluster=40;
 reg [1:0] fault=0;
 integer n,reads=0,data_reads=0,bytes_seen=0,offset,logical_cluster,entry,request,first_data=-1;
 integer expected_offset=0,expected_first_lba=0;
 // Fragmented five-cluster chain: 2 -> 9 -> 4 -> 17 -> 6 -> EOF.
 function integer chain;input integer c;
 begin case(c)2:chain=9;9:chain=4;4:chain=17;17:chain=6;default:chain=28'hfffffff;endcase end endfunction
 function integer ordinal;input integer c;
 begin case(c)2:ordinal=0;9:ordinal=1;4:ordinal=2;17:ordinal=3;6:ordinal=4;default:ordinal=-1;endcase end endfunction
 fat32_file_streamer #(.SEEK_SUPPORT(1),.RANGE_SUPPORT(1),.MAX_VISITED_CLUSTERS(8)) dut(
  .clk(clk),.rst_n(rst_n),.file_start(file_start),.file_partial(file_partial),.start_offset(start_offset),
  .first_cluster(32'd2),.file_size(file_size),.sectors_per_cluster(sectors_per_cluster),
  .fat_start_lba(32'd1),.data_start_lba(32'd100),.max_cluster(max_cluster),
  .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_byte_offset(file_byte_offset),.fs_error(fs_error),.sector_req(sector_req),.sector_lba(sector_lba),
  .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),
  .sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(sector_error));
 always @(posedge clk)if(file_valid)begin
  if(file_byte_offset!==expected_offset+bytes_seen || file_byte!==((expected_offset+bytes_seen)*7+3)%256)
   $fatal(1,"seek byte mismatch offset%0d expected%0d data%0d",file_byte_offset,expected_offset+bytes_seen,file_byte);
  bytes_seen=bytes_seen+1;
 end
 initial forever begin
  @(negedge clk);
  if(sector_req&&!sector_busy)begin
   sector_busy=1;reads=reads+1;request=sector_lba;
   if(request>=100)begin
    if(first_data==-1)begin first_data=request;if(request!=expected_first_lba)$fatal(1,"wrong first data LBA %0d expected %0d",request,expected_first_lba);end
    data_reads=data_reads+1;
    logical_cluster=ordinal((request-100)/sectors_per_cluster+2);
    if(logical_cluster<0)$fatal(1,"read unowned cluster");
    offset=logical_cluster*1024+((request-100)%sectors_per_cluster)*512;
   end
   @(negedge clk);
   for(n=0;n<512;n=n+1)begin
    sector_valid=1;sector_byte_index=n;
    if(request>=100)sector_byte=((offset+n)*7+3)%256;
    else begin
     entry=chain(n/4);
     if(fault==1 && n/4==2)entry=28'hfffffff;
     if(fault==2 && n/4==2)entry=2;
     sector_byte=(entry>>((n%4)*8))&255;
    end
    @(negedge clk);
   end
   sector_valid=0;sector_done=1;@(negedge clk);sector_done=0;sector_busy=0;
  end
 end
 task run;
 input integer target,first_lba,expected_error,expected_bytes,expected_data_reads;
 begin
  repeat(4)@(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  expected_offset=target;bytes_seen=0;reads=0;data_reads=0;first_data=-1;expected_first_lba=first_lba;
  start_offset=target;file_start=1;@(negedge clk);file_start=0;
  wait(file_done);@(negedge clk);
  if(fs_error!=expected_error || bytes_seen!=expected_bytes || data_reads!=expected_data_reads)
   $fatal(1,"seek target%0d result err%h bytes%0d data_reads%0d",target,fs_error,bytes_seen,data_reads);
 end endtask
 initial begin
  // End limits land in a non-final cluster with a valid next FAT entry.
  file_size=1700;run(1100,114,0,600,2);
  file_size=1536;run(1024,114,0,512,1);
  file_size=5000;run(3516,130,0,1484,4);
  // Non-window/full-file mode must still reject premature endpoints.
  file_partial=0;file_size=1700;run(1100,114,8'h23,600,2);
  file_partial=1;fault=1;file_size=5000;run(2048,0,8'h25,0,0);
  fault=2;run(2048,0,8'h23,0,0);
  fault=0;sector_error=1;run(2048,0,8'h10,0,0);
  sector_error=0;run(5000,0,8'h24,0,0);
  $display("PASS bounded FAT windows: partial final sector, fragmented seek, full-file EOC retained; direct cluster traversal, sector prefixes, exact byte offsets/order, last frame, EOF/range/loop/SD errors and skipped payload never read");$finish;
 end
 initial begin #4000000;$fatal(1,"timeout");end
endmodule

