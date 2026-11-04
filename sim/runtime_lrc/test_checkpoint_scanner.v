`timescale 1ns/1ps
module test_checkpoint_scanner;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,scan_start=0,page_start=0;
 reg [1:0] page_select=0;
 reg sector_busy=0,sector_valid=0,sector_done=0;
 reg [7:0] sector_byte=0;reg [8:0] sector_byte_index=0;
 wire sector_req,scan_done;wire [31:0] sector_lba;
 wire [7:0] fs_error;wire [15:0] library_bmp_valid,library_song_valid,library_lrc_valid;
 wire menu_valid;wire [31:0] menu_cluster,menu_size;
 wire [3:0] resource_valid,song_valid,lrc_valid;wire font_valid;
 wire [31:0] resource0_cluster,resource1_cluster,resource2_cluster,resource3_cluster;
 wire [31:0] song0_cluster,song1_cluster,song2_cluster,song3_cluster;
 wire [31:0] lrc0_cluster,lrc1_cluster,lrc2_cluster,lrc3_cluster;
 wire [31:0] resource0_size,resource1_size,resource2_size,resource3_size;
 wire [31:0] song0_size,song1_size,song2_size,song3_size;
 wire [31:0] lrc0_size,lrc1_size,lrc2_size,lrc3_size,font_cluster,font_size;
 wire [1:0] checkpoint_valid;wire [31:0] checkpoint_a_cluster,checkpoint_b_cluster;
 fat32_library_scanner #(.MAX_ROOT_SECTORS(64)) dut(
 .checkpoint_valid(checkpoint_valid),.checkpoint_a_cluster(checkpoint_a_cluster),.checkpoint_b_cluster(checkpoint_b_cluster),
 .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.page_start(page_start),.page_select(page_select),
 .scan_done(scan_done),.fs_error(fs_error),.library_bmp_valid(library_bmp_valid),
 .library_song_valid(library_song_valid),.library_lrc_valid(library_lrc_valid),
 .resource_valid(resource_valid),.song_valid(song_valid),.lrc_valid(lrc_valid),
 .resource0_cluster(resource0_cluster),.resource1_cluster(resource1_cluster),
 .resource2_cluster(resource2_cluster),.resource3_cluster(resource3_cluster),
 .song0_cluster(song0_cluster),.song1_cluster(song1_cluster),.song2_cluster(song2_cluster),.song3_cluster(song3_cluster),
 .lrc0_cluster(lrc0_cluster),.lrc1_cluster(lrc1_cluster),.lrc2_cluster(lrc2_cluster),.lrc3_cluster(lrc3_cluster),
 .resource0_size(resource0_size),.resource1_size(resource1_size),.resource2_size(resource2_size),.resource3_size(resource3_size),
 .song0_size(song0_size),.song1_size(song1_size),.song2_size(song2_size),.song3_size(song3_size),
 .lrc0_size(lrc0_size),.lrc1_size(lrc1_size),.lrc2_size(lrc2_size),.lrc3_size(lrc3_size),
 .menu_valid(menu_valid),.menu_cluster(menu_cluster),.menu_size(menu_size),
 .font_valid(font_valid),.font_cluster(font_cluster),.font_size(font_size),
 .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),.sector_valid(sector_valid),
 .sector_byte(sector_byte),.sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(8'd0));
 reg [7:0] disk[0:131071];
 integer i,j,t,k,p,n,reads=0,fat_reads=0,second_cluster_reads=0,before_reads;
 reg [31:0] lba;
 reg [87:0] shortname;
 task entry;
 input integer address;input [87:0] name;input [7:0] attr;
 input [31:0] cluster,size;
 integer x;
 begin
  for(x=0;x<32;x=x+1)disk[address+x]=0;
  for(x=0;x<11;x=x+1)disk[address+x]=name[(10-x)*8+:8];
  disk[address+11]=attr;disk[address+20]=cluster[23:16];disk[address+21]=cluster[31:24];
  disk[address+26]=cluster[7:0];disk[address+27]=cluster[15:8];
  for(x=0;x<4;x=x+1)disk[address+28+x]=size[x*8+:8];
 end
 endtask
 task check_page;
 input integer page;
 begin
  if(resource_valid!=15||song_valid!=15||lrc_valid!=15)$fatal(1,"page masks wrong");
  if(resource0_cluster!=100+page*4||resource3_cluster!=103+page*4||
     song0_cluster!=200+page*4||song3_cluster!=203+page*4||
     lrc0_cluster!=300+page*4||lrc3_cluster!=303+page*4)$fatal(1,"page %d cluster table misaddressed",page);
  if(resource1_size!=921654||song2_size!=52928124+page*4+2||lrc3_size!=1802)$fatal(1,"page sizes wrong");
 end
 endtask
 initial forever begin
  @(negedge clk);
  if(sector_req&&!sector_busy)begin
   sector_busy=1;lba=sector_lba;reads=reads+1;
   if(lba==1)fat_reads=fat_reads+1;
   if(lba>=82)second_cluster_reads=second_cluster_reads+1;
   if(lba>=256)$fatal(1,"unexpected lba");
   @(negedge clk);
   for(j=0;j<512;j=j+1)begin sector_valid=1;sector_byte_index=j;sector_byte=disk[lba*512+j];@(negedge clk);end
   sector_valid=0;sector_done=1;@(negedge clk);sector_done=0;sector_busy=0;
  end
 end
 initial begin
  for(i=0;i<131072;i=i+1)disk[i]=0;
  disk[0]=8'heb;disk[12]=2;disk[13]=16;disk[14]=1;disk[16]=1;
  disk[34]=1;disk[36]=1;disk[44]=2;disk[510]=8'h55;disk[511]=8'haa;
  disk[512+8]=7; // root cluster 2 -> 7
  disk[512+28]=8'hff;disk[512+29]=8'hff;disk[512+30]=8'hff;disk[512+31]=8'h0f;
  // No end marker in the first root cluster: every unoccupied entry is deleted.
  for(i=2*512;i<18*512;i=i+32)disk[i]=8'he5;
  for(t=0;t<16;t=t+1)begin
   for(k=0;k<3;k=k+1)begin
    if(t==0)p=2*512+k*32;else p=82*512+((t-1)*3+k)*32;
    if(k==0)shortname="PIC1    BMP";else if(k==1)shortname="SONG1   WAV";else shortname="SONG1   LRC";
    if(k==0)begin
     shortname[63:56]=(t+1>=10)?"1":"0"+(t+1);
     shortname[55:48]=(t+1>=10)?"0"+(t+1-10):" ";
    end else begin
     shortname[55:48]=(t+1>=10)?"1":"0"+(t+1);
     shortname[47:40]=(t+1>=10)?"0"+(t+1-10):" ";
    end
    entry(p,shortname,(t%2==0)?8'h00:8'h21,100+k*100+t,k==0?921654:k==1?52928124+t:1802);
   end
  end
  entry(82*512+45*32,"FONT    BIN",0,900,262144);
  entry(82*512+46*32,"MENU    BMP",8'h21,901,921654);
  entry(2*512+3*32,"RESUMA  BIN",0,910,512);
  entry(2*512+4*32,"RESUMB  BIN",0,911,512);
  repeat(3)@(negedge clk);rst_n=1;scan_start=1;@(negedge clk);scan_start=0;
  wait(scan_done);@(negedge clk);
  if(checkpoint_valid!=3 || checkpoint_a_cluster!=910 || checkpoint_b_cluster!=911)$fatal(1,"checkpoint directory discovery");
  if(fs_error!=0||library_bmp_valid!=16'hffff||library_song_valid!=16'hffff||library_lrc_valid!=16'hffff)
   $fatal(1,"library missing tracks pics=%h wav=%h lrc=%h err=%h",library_bmp_valid,library_song_valid,library_lrc_valid,fs_error);
  if(fat_reads!=1||second_cluster_reads!=3||!font_valid||font_size!=262144||font_cluster!=900)
   $fatal(1,"FAT traversal/font mismatch");
  if(!menu_valid||menu_cluster!=901||menu_size!=921654)$fatal(1,"MENU descriptor missing");
  check_page(0);before_reads=reads;
  for(n=1;n<4;n=n+1)begin
   page_select=n;page_start=1;@(negedge clk);page_start=0;
   wait(scan_done);@(negedge clk);check_page(n);
  end
  if(!menu_valid||menu_cluster!=901)$fatal(1,"MENU lost during page cache fetch");
  if(reads!=before_reads)$fatal(1,"page metadata fetch reread the card");
  // Registered bounds must keep the exact >=2 and <=max_cluster semantics.
  entry(2*512+3*32,"RESUMA  BIN",0,1,512);
  entry(2*512+4*32,"RESUMB  BIN",0,32'h10000,512);
  scan_start=1;@(negedge clk);scan_start=0;wait(scan_done);@(negedge clk);
  if(checkpoint_valid!=0 || fs_error!=0)$fatal(1,"invalid checkpoint cluster accepted");
  entry(2*512+3*32,"RESUMA  BIN",0,2,512);
  entry(2*512+4*32,"RESUMB  BIN",0,dut.max_cluster,512);
  scan_start=1;@(negedge clk);scan_start=0;wait(scan_done);@(negedge clk);
  if(checkpoint_valid!=3 || checkpoint_b_cluster!=dut.max_cluster)$fatal(1,"inclusive cluster boundary rejected");
  entry(2*512+3*32,"RESUMA  BIN",1,910,512);
  entry(2*512+4*32,"RESUMB  BIN",0,911,511);
  scan_start=1;@(negedge clk);scan_start=0;wait(scan_done);@(negedge clk);
  if(checkpoint_valid!=0)$fatal(1,"read-only/wrong-size checkpoint accepted");
  // A self-loop must stop with an error instead of exposing partial entries.
  disk[512+8]=2;scan_start=1;@(negedge clk);scan_start=0;
  wait(scan_done);@(negedge clk);
  if(fs_error!=8'h23||library_song_valid!=0||menu_valid)$fatal(1,"self-loop or partial catalog was accepted");
  // A longer loop is bounded by the directory-sector budget.
  disk[512+8]=7;disk[512+28]=2;disk[512+29]=0;disk[512+30]=0;disk[512+31]=0;
  for(i=82*512;i<98*512;i=i+32)disk[i]=8'he5;
  scan_start=1;@(negedge clk);scan_start=0;wait(scan_done);@(negedge clk);
  if(fs_error!=8'h23||library_bmp_valid!=0)$fatal(1,"long root cycle was unbounded");
  // Re-scan an empty card: stale table data and flags must disappear.
  disk[2*512]=0;scan_start=1;@(negedge clk);scan_start=0;
  wait(scan_done);@(negedge clk);
  if(fs_error!=8'h22||library_song_valid!=0||resource_valid!=0||font_valid||menu_valid||song0_cluster!=0)
   $fatal(1,"empty directory retained stale resources");
  $display("PASS 16-track catalog: two root clusters, sector>8, page RAM, attributes, cycle bounds and empty rescan");$finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
