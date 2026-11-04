`timescale 1ns/1ps
module test_spectrum;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0,pcm_valid=0;
  reg signed [15:0] pcm_left=0;
  wire vsync,de,hsync,active;
  wire [11:0] x,y;
  wire [23:0] rgb;
  integer samples=0,tick=0,frames=0,colored=0,axis=0,i,moving=0;
  reg vs_q=1;
  video_timing_ctrl timing(.pclk(clk),.rst_n(rst_n),.hsync(hsync),
    .vsync(vsync),.de(de),.x(x),.y(y));
  promax_audio_spectrum dut(.clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),
    .rgb_in(24'h123456),.pixel_x(x[9:0]),.enable(1'b1),
    .pcm_tap_valid(pcm_valid),.pcm_tap_left(pcm_left),.rgb_out(rgb),
    .spectrum_active(active));
  always @(negedge clk) if(rst_n) begin
    pcm_valid=0;
    if(tick==520) begin
      tick=0; pcm_valid=1;
      pcm_left=$rtoi(12000.0*$sin(6.283185307*1000.0*samples/48000.0));
      samples=samples+1;
    end else tick=tick+1;
    if(de && active && rgb!=24'h406060) colored=colored+1;
    if(de && rgb==24'h406060) axis=axis+1;
    if(vs_q && !vsync) begin
      frames=frames+1;
      if(frames==3) begin
        for(i=0;i<64;i=i+1) if(dut.bar_h[i]>4) moving=moving+1;
        if(colored==0 || axis==0 || moving==0)
          $fatal(1,"spectrum invisible or static: bars=%d axis=%d moving=%d",colored,axis,moving);
        $display("PASS spectrum with final PCM: bars=%0d axis=%0d moving=%0d",colored,axis,moving);
        $finish;
      end
    end
    vs_q=vsync;
  end
  initial begin repeat(5) @(negedge clk); rst_n=1; end
  initial begin #20000000; $fatal(1,"timeout"); end
endmodule
