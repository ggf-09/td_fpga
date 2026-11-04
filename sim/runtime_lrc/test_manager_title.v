`timescale 1ns/1ps
module test_manager_title;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg [1:0] active_song=0;
  wire ready_for_song,lyric_visible,sector_mode,sector_req;
  wire [31:0] sector_lba;
  reg sector_busy=0,sector_valid=0,sector_done=0;
  reg [7:0] sector_byte=0;
  reg [8:0] sector_byte_index=0;
  wire [6:0] cue_count,cue_index;
  wire [11:0] font_addr;
  wire [10:0] text_addr,cue_base;
  wire [15:0] font_data,cue_start;
  wire [7:0] text_data,title_data;
  wire [4:0] cue_len,title_addr,title_count;
  wire font_we,text_we,cue_we,title_we;
  reg [7:0] font_bytes[0:8711],lrc_bytes[0:44],captured_title[0:30];
  // UTF-8 [ti:A你好] followed by two timed lines; literals are bytes so this
  // test does not depend on the simulator's source encoding handling.
  localparam [359:0] LRC = 360'h5b74693a41e4bda0e5a5bd5d0a5b30303a30312e30305d48454c4c4f0a5b30303a30322e30305d574f524c440a;
  integer n,offset,reads=0,cues=0,title_writes=0;
  integer ni_id=-1,hao_id=-1;
  reg [31:0] req_lba;
  wire file_start,file_done,file_valid;
  wire [7:0] file_byte,file_error;
  wire [31:0] file_cluster,file_size,file_offset;
  runtime_lyric_manager dut (
    .clk(clk),.rst_n(rst_n),.sd_free(1'b1),.active_song(active_song),
    .wav_play_en(1'b0),.wav_file_busy(1'b0),.wav_sector_busy(sector_busy),
    .lrc_valid(4'b0001),.lrc0_cluster(32'd3),.lrc0_size(32'd45),
    .lrc1_cluster(32'd0),.lrc2_cluster(32'd0),.lrc3_cluster(32'd0),
    .lrc1_size(32'd0),.lrc2_size(32'd0),.lrc3_size(32'd0),
    .font_valid(1'b1),.font_cluster(32'd2),.font_size(32'd8712),
    .ready_for_song(ready_for_song),.lyric_visible(lyric_visible),
    .sector_mode(sector_mode),.file_start(file_start),
    .file_cluster(file_cluster),.file_size(file_size),
    .file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
    .file_offset(file_offset),.file_error(file_error),
    .cue_count(cue_count),.font_we(font_we),.font_addr(font_addr),.font_data(font_data),
    .text_we(text_we),.text_addr(text_addr),.text_data(text_data),.cue_we(cue_we),
    .cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len),
    .title_we(title_we),.title_addr(title_addr),.title_data(title_data),.title_count(title_count));
  // 生产环境FAT链遍历由sd_card_bmp内共享流读器承担；这里本地实例补回，扇区模型保持不变
  fat32_file_streamer #(.MAX_VISITED_CLUSTERS(8192)) u_lrc_file (
    .clk(clk),.rst_n(rst_n && sector_mode),.file_start(file_start),
    .start_offset(32'd0),
    .first_cluster(file_cluster),.file_size(file_size),
    .sectors_per_cluster(8'd32),.fat_start_lba(32'd1),
    .data_start_lba(32'd100),.max_cluster(32'd1000),
    .file_busy(),.file_done(file_done),.file_valid(file_valid),
    .file_byte(file_byte),.file_byte_offset(file_offset),.fs_error(file_error),
    .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),
    .sector_valid(sector_valid),.sector_byte(sector_byte),
    .sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(8'd0));
  always @(posedge clk) begin
    if(cue_we) cues=cues+1;
    if(title_we) begin
      if(title_addr>=31) $fatal(1,"title address out of range");
      captured_title[title_addr]=title_data;
      title_writes=title_writes+1;
    end
  end
  initial forever begin
    @(negedge clk);
    if(sector_req && !sector_busy) begin
      sector_busy=1; req_lba=sector_lba; reads=reads+1;
      @(negedge clk);
      for(n=0;n<512;n=n+1) begin
        sector_valid=1; sector_byte_index=n; sector_byte=0;
        if(req_lba>=100 && req_lba<=117) begin
          offset=(req_lba-100)*512+n;
          if(offset<8712) sector_byte=font_bytes[offset];
        end else if(req_lba==132) begin
          if(n<45) sector_byte=lrc_bytes[n];
        end else if(req_lba==1) begin
          if(n>=8 && n<16) sector_byte=(n==11 || n==15)?8'h0f:8'hff;
        end else $fatal(1,"unexpected LBA %0d",req_lba);
        @(negedge clk);
      end
      sector_valid=0; sector_done=1;
      @(negedge clk); sector_done=0; sector_busy=0;
    end
  end
  initial begin
    $readmemh("font.hex",font_bytes);
    // Add ASCII A to an unused index; existing generated font contains the
    // two Chinese glyphs above index 127, exercising the full eight-bit IDs.
    font_bytes[5]=251;font_bytes[6]=0;
    font_bytes[8+250*2]=8'h41;font_bytes[9+250*2]=0;
    for(integer j=0;j<256;j=j+1) begin
      if({font_bytes[9+j*2],font_bytes[8+j*2]}==16'h4f60) ni_id=j;
      if({font_bytes[9+j*2],font_bytes[8+j*2]}==16'h597d) hao_id=j;
    end
    if(ni_id<128 || hao_id<128) $fatal(1,"test font must contain high-index Chinese glyphs");
    for(integer j=0;j<45;j=j+1) lrc_bytes[j]=LRC[(44-j)*8 +: 8];
    repeat(5) @(negedge clk);rst_n=1;
    wait(ready_for_song);@(negedge clk);
    if(!lyric_visible || cue_count!=2 || cues!=2 || title_count!=3 || title_writes!=3 || reads!=21)
      $fatal(1,"load failed visible=%b count=%0d cues=%0d title_count=%0d writes=%0d reads=%0d",lyric_visible,cue_count,cues,title_count,title_writes,reads);
    if(captured_title[0]!=250 || captured_title[1]!=ni_id || captured_title[2]!=hao_id)
      $fatal(1,"title mapping failed: %0d %0d %0d",captured_title[0],captured_title[1],captured_title[2]);
    active_song=1;
    #1;if(ready_for_song || lyric_visible) $fatal(1,"track change must invalidate visible metadata");
    wait(ready_for_song);@(negedge clk);
    if(lyric_visible || title_writes!=3 || reads!=21)
      $fatal(1,"missing LRC should hide title/lyrics without SD reads");
    active_song=0;
    wait(!ready_for_song);wait(ready_for_song);@(negedge clk);
    if(!lyric_visible || cue_count!=2 || title_count!=3 || cues!=4 || title_writes!=6 || reads!=23)
      $fatal(1,"track reload failed");
    $display("PASS manager FAT title read: UTF-8 mapping, shared-font reuse, two cues, missing LRC hides title, reload");
    $finish;
  end
  initial begin #10000000;$fatal(1,"timeout");end
endmodule
