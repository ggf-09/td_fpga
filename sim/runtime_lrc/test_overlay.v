`timescale 1ns/1ps
module test_overlay;
  reg clk=0, sd_clk=0, rst_n=0, vsync=1, de=0;
  reg [9:0] pixel_x=0;
  reg ready_sd=0, cue_we=0, text_we=0, font_we=0;
  reg [6:0] cue_index=0, cue_count_sd=1;
  reg [15:0] cue_start=0, font_data=16'h8000, play_cs=1;
  reg [10:0] cue_base=0, text_addr=0;
  reg [11:0] font_addr=3200;
  reg [4:0] cue_len=31;
  reg [7:0] text_data=200;
  wire [23:0] rgb_out;
  wire lyric_active;
  always #5 clk=~clk;
  always #5 sd_clk=~sd_clk;
  runtime_lyric_overlay #(.LYRIC_Y(2),.H_ACT(640)) dut (
    .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),.rgb_in(24'h123456),
    .pixel_x(pixel_x),.enable(1'b1),.play_cs(play_cs),.sd_clk(sd_clk),
    .ready_sd(ready_sd),.cue_count_sd(cue_count_sd),.cue_we(cue_we),
    .cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),
    .cue_len(cue_len),.text_we(text_we),.text_addr(text_addr),
    .text_data(text_data),.font_we(font_we),.font_addr(font_addr),
    .font_data(font_data),.rgb_out(rgb_out),.lyric_active(lyric_active));
  task line;
    input integer n;
    integer x;
    begin
      de=1;
      for (x=0;x<640;x=x+1) begin
        pixel_x=x;
        #1;
        if (n==2 && (x==41 || x==581) && rgb_out!==24'hffe000) begin
          $display("FAIL glyph pixel: rgb=%h",rgb_out); $fatal;
        end
        if (n==2 && x==42 && rgb_out!==24'h123456) begin
          $display("FAIL background pixel: rgb=%h",rgb_out); $fatal;
        end
        @(negedge clk);
      end
      de=0;
      repeat(160) @(negedge clk);
    end
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    cue_we=1; text_we=1; font_we=1;
    @(negedge clk); cue_we=0; font_we=0;
    for(integer j=1;j<31;j=j+1) begin
      text_addr=j;
      @(negedge clk);
    end
    text_we=0; ready_sd=1;
    repeat(100) @(negedge clk);
    line(0); line(1); line(2);
    $display("PASS runtime lyric overlay"); $finish;
  end
endmodule
