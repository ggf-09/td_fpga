`timescale 1ns/1ps
module test_scanner_attributes;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,scan_start=0,sector_busy=0,sector_valid=0,sector_done=0;
 reg [7:0] sector_byte=0;
 reg [8:0] sector_byte_index=0;
 wire scan_done,sector_req;
 wire [31:0] sector_lba;
 wire [3:0] resource_valid,song_valid,lrc_valid;
 wire font_valid;
 wire [31:0] resource2_cluster,song2_cluster,lrc2_cluster,font_cluster;
 reg [7:0] boot[0:511],root[0:4095];
 integer i,j,reads=0,cases=0;
 reg [31:0] lba;
 fat32_volume_scanner dut(
 .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.scan_done(scan_done),
 .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),
 .sector_valid(sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_byte_index),
 .sector_done(sector_done),.sector_error(8'd0),
 .resource_valid(resource_valid),.song_valid(song_valid),.lrc_valid(lrc_valid),.font_valid(font_valid),
 .resource2_cluster(resource2_cluster),.song2_cluster(song2_cluster),.lrc2_cluster(lrc2_cluster),.font_cluster(font_cluster));
 task entry;
 input integer pos;
 input [87:0] name;
 input [7:0] attr;
 input [31:0] cluster,size;
 integer k;
 begin
  for(k=0;k<11;k=k+1)root[pos*32+k]=name[(10-k)*8+:8];
  root[pos*32+11]=attr;
  root[pos*32+20]=cluster[23:16];root[pos*32+21]=cluster[31:24];
  root[pos*32+26]=cluster[7:0];root[pos*32+27]=cluster[15:8];
  for(k=0;k<4;k=k+1)root[pos*32+28+k]=size[k*8+:8];
 end
 endtask
 initial forever begin
  @(negedge clk);
  if(sector_req&&!sector_busy)begin
   sector_busy=1;lba=sector_lba;reads=reads+1;@(negedge clk);
   for(j=0;j<512;j=j+1)begin
    sector_valid=1;sector_byte_index=j;
    if(lba==0)sector_byte=boot[j];
    else if(lba>=2&&lba<10)sector_byte=root[(lba-2)*512+j];
    else $fatal(1,"Unexpected LBA %0d",lba);
    @(negedge clk);
   end
   sector_valid=0;sector_done=1;@(negedge clk);sector_done=0;sector_busy=0;
  end
 end
 task run;
 input [7:0] attr;
 input accepted;
 begin
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  for(i=0;i<4096;i=i+1)root[i]=0;
  entry(0,"PIC1    BMP",8'h20,3,921654);entry(1,"PIC2    BMP",8'h20,4,921654);
  entry(2,"SONG1   WAV",8'h20,5,1000);entry(3,"SONG2   WAV",8'h20,6,1000);
  // Invalid entries have matching names but must never count as files.
  entry(4,"PIC4    BMP",8'h10,99,921654);entry(5,"SONG4   WAV",8'h08,99,1000);
  entry(6,"SONG4   LRC",8'h0f,99,1000);
  entry(16,"PIC3    BMP",attr,7,921654);entry(17,"SONG3   WAV",attr,8,52928124);
  entry(18,"SONG3   LRC",attr,9,1802);entry(19,"FONT    BIN",attr,10,65536);
  reads=0;scan_start=1;@(negedge clk);scan_start=0;
  wait(scan_done);@(negedge clk);
  if(resource_valid!==(accepted?4'b0111:4'b0011)||song_valid!==(accepted?4'b0111:4'b0011)||
   lrc_valid!==(accepted?4'b0100:4'b0000)||font_valid!==accepted)
    $fatal(1,"attribute %h recognition incorrect pics=%b songs=%b lrc=%b font=%b",attr,resource_valid,song_valid,lrc_valid,font_valid);
  if(accepted&&(resource2_cluster!=7||song2_cluster!=8||lrc2_cluster!=9||font_cluster!=10))
    $fatal(1,"wrong resource mapping");
  if(reads!=9)$fatal(1,"scan terminated before second sector or read beyond bound");
  cases=cases+1;
 end
 endtask
 initial begin
  for(i=0;i<512;i=i+1)boot[i]=0;
  boot[0]=8'heb;boot[11]=0;boot[12]=2;boot[13]=8;boot[14]=1;boot[16]=1;
  boot[32]=0;boot[33]=0;boot[34]=1;boot[36]=1;boot[44]=2;boot[510]=8'h55;boot[511]=8'haa;
  run(8'h20,1);run(8'h00,1);run(8'h01,1);run(8'h02,1);run(8'h04,1);run(8'h21,1);run(8'h27,1);
  run(8'h10,0);run(8'h08,0);run(8'h0f,0);
  $display("PASS scanner attributes: %0d cases, third track on second root sector, directory/label/LFN rejected",cases);$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
