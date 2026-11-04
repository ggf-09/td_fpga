`timescale 1ns/1ps
module test_lrc_loader;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, start_font=0,start_lrc=0,file_valid=0,file_done=0;
  reg [7:0] file_byte=0,file_error=0;
  reg [31:0] file_offset=0;
  wire font_ready,lyric_ready,parse_done,font_we,text_we,cue_we;
  wire [6:0] cue_count,cue_index;
  wire [11:0] font_addr;
  wire [10:0] text_addr,cue_base;
  wire [15:0] font_data,cue_start;
  wire [7:0] text_data;
  wire [4:0] cue_len;
  wire title_we;
  wire [4:0] title_addr,title_count;
  wire [7:0] title_data;
  reg [7:0] font_bytes[0:8711];
  reg [7:0] lrc_bytes[0:63];
  integer i, seen_cues=0, seen_chars=0;
  fat_lrc_loader dut(.start_timing(1'b0),.timing_clk(1'b0),.timing_read_addr(12'd0),.timing_read_data(),.timing_available(),.timing_ready(),.*);
  always @(posedge clk) begin
    if (cue_we) begin
      seen_cues=seen_cues+1;
      $display("CUE %0d time=%0d base=%0d len=%0d",cue_index,cue_start,cue_base,cue_len);
      if (seen_cues==1 && (cue_start!=123 || cue_len!=5)) $fatal(1,"cue 1 mismatch");
      if (seen_cues==2 && (cue_start!=345 || cue_len!=5)) $fatal(1,"cue 2 mismatch");
      if (seen_cues==3 && (cue_start!=400 || cue_len!=2 || cue_base!=10)) $fatal(1,"cue 3 mismatch");
    end
    if (text_we) begin
      seen_chars=seen_chars+1;
      if(text_data<128) $fatal(1,"glyph index high bit lost");
    end
  end
  initial begin
    $readmemh("font.hex",font_bytes);
    $readmemh("lrc.hex",lrc_bytes,0,48);
    repeat(5) @(negedge clk); rst_n=1;
    @(negedge clk); start_font=1;
    @(negedge clk); start_font=0;
    for(i=0;i<8712;i=i+1) begin
      file_valid=1; file_offset=i; file_byte=font_bytes[i];
      @(negedge clk);
    end
    file_valid=0; file_done=1;
    @(negedge clk); file_done=0;
    wait(parse_done); @(negedge clk);
    if(!font_ready) $fatal(1,"font not ready");
    start_lrc=1;
    @(negedge clk); start_lrc=0;
    for(i=0;i<49;i=i+1) begin
      file_valid=1; file_offset=i; file_byte=lrc_bytes[i];
      @(negedge clk);
    end
    file_valid=0; file_done=1;
    @(negedge clk); file_done=0;
    wait(parse_done); @(negedge clk);
    if(!lyric_ready || cue_count!=3 || seen_cues!=3 || seen_chars!=12)
      $fatal(1,"LRC result mismatch ready=%b count=%0d cues=%0d chars=%0d",lyric_ready,cue_count,seen_cues,seen_chars);
    $display("PASS runtime LRC parser"); $finish;
  end
  initial begin #10000000; $fatal(1,"timeout"); end
endmodule
