`timescale 1ns/1ps
module test_video_startup;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  wire raw_hs,raw_vs,raw_de,osd_de_out;
  wire [11:0] x,y;
  wire [23:0] osd_rgb,rgb,axis_rgb;
  wire hs,vs,de,valid,sof;
  wire player_enable_pix=1'b0; // No image loaded for the entire test.
  `include "startup_de_connection.vh"
  integer cycles=0,pixels=0,yellow=0,red=0,frames=0;
  video_timing_ctrl timing(.pclk(clk),.rst_n(rst_n),.hsync(raw_hs),
    .vsync(raw_vs),.de(raw_de),.x(x),.y(y));
  osd_overlay_24 osd(.clk(clk),.rst_n(rst_n),.vsync(raw_vs),.de(raw_de),
    .rgb_in(24'd0),.pixel_x(x[9:0]),.active_index(2'd0),
    .auto_enabled(1'b0),.error_code(8'h47),.rgb_out(osd_rgb),
    .de_out(osd_de_out),.osd_active());
  rgb_video_adapter adapter(.pclk(clk),.rst_n(rst_n),.hs_in(raw_hs),
    .vs_in(raw_vs),.de_in(adapter_de),.rgb_in(osd_rgb),.video_clk(),
    .video_hs(hs),.video_vs(vs),.video_de(de),.video_rgb(rgb));
  video_rgb_to_axis_640x480 axis_out(.I_clk(clk),.I_rst(!rst_n),
    .I_vs(vs),.I_de(de),.I_rgb(rgb),.O_video_user(sof),
    .O_video_valid(valid),.O_video_last(),.O_video_data(axis_rgb));
  always @(negedge clk) if(rst_n) begin
    cycles=cycles+1;
    if(valid) begin
      pixels=pixels+1;
      if(axis_rgb==24'hffff00) yellow=yellow+1;
      if(axis_rgb==24'hff4444) red=red+1;
    end
    if(valid && sof) frames=frames+1;
    if(cycles==840000) begin
      if(pixels!=614400 || frames!=2 || yellow==0 || red==0)
        $fatal(1,"startup video missing: pixels=%0d SOF=%0d initialOSD=%0d errorOSD=%0d",pixels,frames,yellow,red);
      $display("PASS video before first image: 2 complete AXIS frames, initial and error OSD visible");
      $finish;
    end
  end
  initial begin repeat(5) @(negedge clk); rst_n=1; end
  initial begin #9000000; $fatal(1,"video startup timeout"); end
endmodule
