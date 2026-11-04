`timescale 1ns/1ps
module test_manager_library_font;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg [1:0] active_song=0;
  reg [3:0] font_bank=12;
  reg sd_free=1;
  reg [31:0] font_size=262144;
  wire ready_for_song,lyric_visible,sector_mode,sector_req;
  wire [31:0] sector_lba;
  reg sector_busy=0,sector_valid=0,sector_done=0;
  reg [7:0] sector_byte=0;
  reg [8:0] sector_byte_index=0;
  wire [6:0] cue_count,cue_index;
  wire [11:0] font_addr;
  wire [10:0] text_addr,cue_base;
  wire [15:0] font_data,cue_start;
  wire [7:0] text_data;
  wire [4:0] cue_len;
  wire font_we,text_we,cue_we;
  reg [7:0] font_bytes[0:262143],lrc_bytes[0:63];
  integer n,offset,reads=0,cues=0,stage=0;
  reg [31:0] req_lba;
  wire file_start,file_done,file_valid;
  wire [7:0] file_byte,file_error;
  wire [31:0] file_cluster,file_size,file_offset;
  runtime_lyric_manager #(.LIBRARY_MODE(1)) dut (
    .clk(clk),.rst_n(rst_n),.sd_free(sd_free),.font_bank(font_bank),.active_song(active_song),
    .wav_play_en(1'b0),.wav_file_busy(1'b0),.wav_sector_busy(sector_busy),
    .lrc_valid(4'b1011),.lrc0_cluster(32'd6),.lrc0_size(32'd49),
    .lrc1_cluster(32'd6),.lrc2_cluster(32'd0),.lrc3_cluster(32'd6),
    .lrc1_size(32'd49),.lrc2_size(32'd0),.lrc3_size(32'd49),
    .font_valid(1'b1),.font_cluster(32'd2),.font_size(font_size),
    .ready_for_song(ready_for_song),.lyric_visible(lyric_visible),
    .sector_mode(sector_mode),.file_start(file_start),
    .file_cluster(file_cluster),.file_size(file_size),
    .file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
    .file_offset(file_offset),.file_error(file_error),
    .cue_count(cue_count),.font_we(font_we),.font_addr(font_addr),.font_data(font_data),
    .text_we(text_we),.text_addr(text_addr),.text_data(text_data),.cue_we(cue_we),
    .cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len));
  // 生产环境FAT链遍历由sd_card_bmp内共享流读器承担；这里本地实例补回，扇区模型保持不变
  fat32_file_streamer #(.MAX_VISITED_CLUSTERS(8192)) u_lrc_file (
    .clk(clk),.rst_n(rst_n && sector_mode),.file_start(file_start),
    .start_offset(32'd0),
    .first_cluster(file_cluster),.file_size(file_size),
    .sectors_per_cluster(8'd128),.fat_start_lba(32'd1),
    .data_start_lba(32'd100),.max_cluster(32'd1000),
    .file_busy(),.file_done(file_done),.file_valid(file_valid),
    .file_byte(file_byte),.file_byte_offset(file_offset),.fs_error(file_error),
    .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),
    .sector_valid(sector_valid),.sector_byte(sector_byte),
    .sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(8'd0));
  always @(posedge clk) begin
    if(cue_we) cues=cues+1;
    if(text_we && text_addr==0) begin
      if(stage!=0 && text_data!=2) $fatal(1,"track 2 did not load its own font");
      if(stage==0 && text_data<128) $fatal(1,"track 1 font was not restored");
    end
  end
  initial forever begin
    @(negedge clk);
    if(sector_req && !sector_busy) begin
      sector_busy=1; req_lba=sector_lba; reads=reads+1;
      @(negedge clk);
      for(n=0;n<512;n=n+1) begin
        sector_valid=1; sector_byte_index=n; sector_byte=0;
        if(req_lba>=100 && req_lba<=611) begin
          offset=(req_lba-100)*512+n;
          sector_byte=font_bytes[offset];
        end else if(req_lba==612) begin
          if(n<49) sector_byte=lrc_bytes[n];
        end else if(req_lba==1) begin
          case(n/4)
            2:sector_byte=n%4==0?3:0;
            3:sector_byte=n%4==0?4:0;
            4:sector_byte=n%4==0?5:0;
            5,6:sector_byte=n%4==3?8'h0f:8'hff;
          endcase
        end else $fatal(1,"unexpected LBA %0d",req_lba);
        @(negedge clk);
      end
      sector_valid=0; sector_done=1;
      @(negedge clk); sector_done=0; sector_busy=0;
    end
  end
  initial begin
    $readmemh("library_font.hex",font_bytes); $readmemh("lrc.hex",lrc_bytes,0,48);
    repeat(5) @(negedge clk); rst_n=1;
    wait(ready_for_song); @(negedge clk);
    if(!lyric_visible || cue_count!=3 || cues!=3 || reads!=518) $fatal(1,"track 1 failed");
    stage=1; active_song=3;font_bank=15;
    wait(!ready_for_song); wait(ready_for_song); @(negedge clk);
    if(!lyric_visible || cues!=6 || reads!=1036) $fatal(1,"track 2 failed");
    stage=2; active_song=0;font_bank=0;
    wait(!ready_for_song); wait(ready_for_song); @(negedge clk);
    if(!lyric_visible || cues!=9 || reads!=1554) $fatal(1,"track 1 reload failed");
    if(dut.font_song!=0)$fatal(1,"global font bank not restored");
    sd_free=0;repeat(4)@(negedge clk);font_size=65536;font_bank=4;sd_free=1;
    wait(ready_for_song);@(negedge clk);
    if(lyric_visible||reads!=1554)$fatal(1,"legacy 4-slot font was reused for track 5");
    $display("PASS 16-bank font: real four-cluster FAT file, banks 12/15/0, slot-zero map differs, legacy-bank bounds"); $finish;
  end
  initial begin #30000000; $fatal(1,"timeout"); end
endmodule
