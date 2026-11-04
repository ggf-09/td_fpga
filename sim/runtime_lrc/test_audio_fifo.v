`timescale 1ns/1ps
module test_audio_fifo;
  reg wr_clk=0,rd_clk=0;
  always #5 wr_clk=~wr_clk;
  always #20 rd_clk=~rd_clk;
  reg wr_rst_n=0,rd_rst_n=0,file_valid=0,file_done=0;
  reg [7:0] file_byte=0;
  reg [31:0] file_byte_offset=0;
  wire can_read_sector,format_error,stream_end,sample_valid;
  wire signed [15:0] sample_left,sample_right;
  wire [31:0] sample_counter,underflow_count;
  reg [1:0] tick_count=0;
  reg [2:0] warmup=0;
  wire sample_tick=warmup==7 && tick_count==0;
  reg [7:0] bytes[0:20043];
  integer i,seen=0,stalls=0;
  reg paused=0;
  integer paused_ticks=0;
  reg [31:0] frozen_count;
  always @(posedge rd_clk) tick_count<=tick_count+1'b1;
  always @(posedge rd_clk) if(rd_rst_n && warmup!=7) warmup<=warmup+1'b1;
  fat_wav_player #(.ADDR_WIDTH(11)) dut(
    .wr_clk(wr_clk),.wr_rst_n(wr_rst_n),.file_valid(file_valid),
    .file_byte(file_byte),.file_byte_offset(file_byte_offset),.file_done(file_done),
    .file_error(8'd0),.can_read_sector(can_read_sector),.format_error(format_error),
    .stream_end(stream_end),.rd_clk(rd_clk),.rd_rst_n(rd_rst_n),.sample_tick(sample_tick),
    .paused(paused),.sample_ready(1'b1),.sample_valid(sample_valid),.sample_left(sample_left),
    .sample_right(sample_right),.sample_counter(sample_counter),.underflow_count(underflow_count));
  always @(posedge rd_clk) if(rd_rst_n && sample_valid && paused) begin
    if(sample_left!==0 || sample_right!==0 || sample_counter!==frozen_count)
      $fatal(1,"Pause changed playback position or failed to send silence");
    paused_ticks=paused_ticks+1;
  end
  always @(posedge rd_clk) if(rd_rst_n && sample_valid && !paused && seen<5000) begin
    if(sample_left!==seen || $signed(sample_right)!==-seen)
      $fatal(1,"FIFO ordering error sample %0d L=%0d R=%0d",seen,sample_left,sample_right);
    seen=seen+1;
  end
  initial begin
    wait(file_byte_offset>=7000); @(negedge rd_clk); rd_rst_n=1;
  end
  initial begin
    wait(seen==500);
    // Change pause between sample ticks, after the previous output was consumed.
    @(negedge rd_clk); while(sample_valid) @(negedge rd_clk);
    frozen_count=sample_counter; paused=1;
    repeat(10000) @(negedge rd_clk);
    while(sample_valid) @(negedge rd_clk);
    if(can_read_sector || stream_end || paused_ticks<100)
      $fatal(1,"Pause failed to fill/backpressure FIFO or maintain cadence");
    paused=0;
  end
  initial begin
    $readmemh("audio.hex",bytes);
    repeat(5) @(negedge wr_clk); wr_rst_n=1;
    for(i=0;i<20044;i=i+1) begin
      if(i%512==0) while(!can_read_sector) begin
        stalls=stalls+1; file_valid=0; @(negedge wr_clk);
      end
      file_valid=1; file_byte=bytes[i]; file_byte_offset=i;
      @(negedge wr_clk);
    end
    file_valid=0; file_done=1;
    @(negedge wr_clk); file_done=0;
    wait(stream_end); repeat(5) @(negedge rd_clk);
    if(seen!=5000 || format_error || stalls==0 || underflow_count!=0)
      $fatal(1,"audio result count=%0d format=%b stalls=%0d underflows=%0d",seen,format_error,stalls,underflow_count);
    $display("PASS audio pause/resume: 5000 ordered stereo frames, frozen counter, silent cadence, FIFO backpressure and wraparound");
    $finish;
  end
  initial begin #10000000; $fatal(1,"timeout"); end
endmodule
