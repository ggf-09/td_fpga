`timescale 1ns/1ps
module test_title_overlay;
  reg clk=0,sd_clk=0,rst_n=0,vsync=1,de=0;
  reg [9:0] pixel_x=0;
  reg ready_sd=0,title_ready_sd=0,cue_we=0,text_we=0,font_we=0,title_we=0;
  reg enable=1;
  reg [6:0] cue_count_sd=1,cue_index=0;
  reg [15:0] cue_start=0,play_cs=1,font_data=0;
  reg [10:0] cue_base=0,text_addr=0;
  reg [4:0] cue_len=31,title_addr=0,title_count_sd=31;
  reg [7:0] text_data=201,title_data=200;
  reg [11:0] font_addr=0;
  wire [23:0] rgb_out;
  integer frame_kind=0;
  always #5 clk=~clk;
  always #7 sd_clk=~sd_clk;
  runtime_lyric_overlay #(.TITLE_Y(4),.LYRIC_Y(40)) dut (
    .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),.rgb_in(24'h123456),
    .pixel_x(pixel_x),.enable(enable),.play_cs(play_cs),.sd_clk(sd_clk),
    .ready_sd(ready_sd),.cue_count_sd(cue_count_sd),.cue_we(cue_we),
    .cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),
    .cue_len(cue_len),.text_we(text_we),.text_addr(text_addr),
    .text_data(text_data),.font_we(font_we),.font_addr(font_addr),
    .font_data(font_data),.title_we(title_we),.title_addr(title_addr),
    .title_data(title_data),.title_count_sd(title_count_sd),
    .title_ready_sd(title_ready_sd),.rgb_out(rgb_out),.lyric_active());

  task expect_pixel;
    input [23:0] wanted;
    input integer y,x;
    begin
      if(rgb_out!==wanted) begin
        $display("FAIL frame=%0d y=%0d x=%0d rgb=%h wanted=%h",frame_kind,y,x,rgb_out,wanted);
        $fatal;
      end
    end
  endtask
  task frame;
    input integer kind;
    integer y,x;
    begin
      frame_kind=kind;
      @(negedge clk);vsync=0;de=0;
      repeat(10) @(negedge clk);
      vsync=1;
      repeat(100) @(negedge clk);
      for(y=0;y<64;y=y+1) begin
        de=1;
        for(x=0;x<640;x=x+1) begin
          pixel_x=x; #1;
          if(y==4 || y==19) begin
            if(kind==0 || kind==1) begin
              if(x==41 || x==581) expect_pixel(24'hffe000,y,x);
              if(x==43 || (x==42 && y==4)) expect_pixel(24'h123456,y,x);
            end else if(kind==2) begin
              if(x==41 || x==581 || x==317) expect_pixel(24'h123456,y,x);
            end else begin
              if(x==317 || x==335) expect_pixel(24'hffe000,y,x);
              if(x==41 || x==581 || x==302) expect_pixel(24'h123456,y,x);
            end
          end
          if(y==40 || y==55) begin
            if(x==42 || x==582)
              expect_pixel(kind==0 || !enable ? 24'h123456 : 24'hffe000,y,x);
            if(x==41) expect_pixel(24'h123456,y,x);
          end
          @(negedge clk);
        end
        de=0;repeat(160) @(negedge clk);
      end
    end
  endtask
  initial begin
    repeat(3) @(negedge clk);rst_n=1;
    for(integer glyph=200;glyph<=202;glyph=glyph+1) begin
      for(integer row=0;row<16;row=row+1) begin
        @(negedge sd_clk);font_we=1;font_addr=glyph*16+row;
        font_data=glyph==200 ? 16'h8000 : glyph==201 ? 16'h4000 : 16'h0001;
      end
    end
    @(negedge sd_clk);font_we=0;title_we=1;
    for(integer j=0;j<31;j=j+1) begin
      title_addr=j;@(negedge sd_clk);
    end
    title_we=0;title_ready_sd=1;
    frame(0); // A title is visible even with lyric_ready low and no cues.
    @(negedge sd_clk);cue_we=1;text_we=1;text_addr=0;
    @(negedge sd_clk);cue_we=0;
    for(integer j=1;j<31;j=j+1) begin text_addr=j;@(negedge sd_clk);end
    text_we=0;ready_sd=1;
    frame(1); // The title and all 31 subtitle glyphs share the font port.
    @(negedge sd_clk);title_ready_sd=0;
    frame(2); // A track change suppresses the old title immediately after CDC.
    @(negedge sd_clk);title_count_sd=2;title_we=1;title_data=202;title_addr=0;
    @(negedge sd_clk);title_addr=1;
    @(negedge sd_clk);title_we=0;title_ready_sd=1;
    frame(3); // A shorter replacement cannot retain the previous title width.
    enable=0;frame(3); // Ordered EOF hides lyrics but retains the loaded title.
    $display("PASS shared-font title overlay: title-only, first/last glyph and row, lyrics, invalidation, replacement, stopped title");
    $finish;
  end
endmodule
