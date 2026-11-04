`timescale 1ns/1ps
// Render only the two actual new UI stages. Existing spectrum, diagnostic
// overlays and timed subtitle stages are intentionally not simulated here.
module render_playback_ui;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,vsync=1,de=0,ready=0;
  reg [9:0] pixel_x=0,pixel_y=0;
  reg [23:0] rgb_in=0;
  reg font_we=0,title_we=0;
  reg [11:0] font_addr=0;
  reg [15:0] font_data=0;
  reg [4:0] title_addr=0,title_count=0;
  reg [7:0] title_data=0;
  reg [31:0] total_frames=0;
  reg [23:0] background[0:307199];
  reg [15:0] font_rows[0:4095];
  reg [7:0] title_ids[0:30];
  wire [23:0] title_rgb,rgb_out;
  integer file_handle;
  runtime_lyric_overlay title (
    .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),.rgb_in(rgb_in),
    .pixel_x(pixel_x),.enable(1'b1),.play_cs(16'd12300),.sd_clk(clk),
    .ready_sd(1'b0),.cue_count_sd(7'd0),.cue_we(1'b0),.cue_index(7'd0),
    .cue_start(16'd0),.cue_base(11'd0),.cue_len(5'd0),
    .text_we(1'b0),.text_addr(11'd0),.text_data(8'd0),
    .font_we(font_we),.font_addr(font_addr),.font_data(font_data),
    .title_we(title_we),.title_addr(title_addr),.title_data(title_data),
    .title_count_sd(title_count),.title_ready_sd(ready),
    .rgb_out(title_rgb),.lyric_active());
  playback_status_overlay status (
    .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),
    .pixel_x(pixel_x),.pixel_y(pixel_y),.rgb_in(title_rgb),
    .sample_count(32'd5904000),.total_frames(total_frames),
    .song_index(2'd0),.stream_active(ready),.wav_stream_end(1'b0),
    .paused(1'b0),.stopped(1'b0),.play_mode(2'd0),
    .show_text(1'b1),.transition_active(2'd0),
    .rgb_out(rgb_out),.osd_active());

  task frame;
    input integer capture;
    integer y,x;
    begin
      // VGA-equivalent 45 blank lines and 160 blank pixels per active row.
      @(negedge clk);vsync=0;de=0;
      repeat(1600) @(negedge clk);
      vsync=1;
      repeat(34400) @(negedge clk);
      for(y=0;y<480;y=y+1) begin
        pixel_y=y;de=1;
        for(x=0;x<640;x=x+1) begin
          pixel_x=x;rgb_in=background[y*640+x];#1;
          if(capture) $fwrite(file_handle,"%06h\n",rgb_out);
          @(negedge clk);
        end
        de=0;repeat(160) @(negedge clk);
      end
    end
  endtask
  initial begin
    $readmemh("background.hex",background);
    $readmemh("font_rows.hex",font_rows);
    $readmemh("title_ids.hex",title_ids);
    if(!$value$plusargs("title_count=%d",title_count)) $fatal(1,"title_count missing");
    if(!$value$plusargs("total_frames=%d",total_frames)) $fatal(1,"total_frames missing");
    repeat(5) @(negedge clk);rst_n=1;
    font_we=1;
    for(integer j=0;j<4096;j=j+1) begin
      font_addr=j;font_data=font_rows[j];@(negedge clk);
    end
    font_we=0;title_we=1;
    for(integer j=0;j<title_count;j=j+1) begin
      title_addr=j;title_data=title_ids[j];@(negedge clk);
    end
    title_we=0;ready=1;
    frame(0);frame(0);
    file_handle=$fopen("ui_pixels.hex","w");
    if(!file_handle) $fatal(1,"cannot open pixel dump");
    frame(1);$fclose(file_handle);
    if(status.elapsed_bcd!==20'h00203 || status.total_bcd!==20'h00457)
      $fatal(1,"unexpected UI clock digits: %h/%h",status.elapsed_bcd,status.total_bcd);
    $display("PASS UI render: 307200 HDL RGB pixels, two warmup frames, elapsed 002:03 / 004:57, fill=%0d/608",status.progress_pixels);
    $finish;
  end
endmodule
