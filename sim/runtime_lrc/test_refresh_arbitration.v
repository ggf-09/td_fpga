`timescale 1ns/1ps
module test_refresh_arbitration;
  reg src_clk=0,clk=0,pix_clk=0;
  always #5 src_clk=~src_clk;
  always #4 clk=~clk;
  always #20 pix_clk=~pix_clk;
  reg rst_n=0,src_we=0;
  reg [20:0] src_addr=0;
  reg [31:0] src_data=0;
  wire full,overflow,wr_en,wr_active,idle,hold_new,req,fault;
  wire [20:0] wr_addr;
  wire [31:0] wr_data;
  reg manual_rd_active=0,manual_rd_en=0,refresh_active=0;
  wire actual_rd_active,actual_rd_en;
  wire rd_active=manual_rd_active || actual_rd_active;
  wire rd_en=manual_rd_en || actual_rd_en;
  wire [20:0] actual_rd_addr;
  reg [7:0] rd_pipe=0;
  reg [31:0] data_pipe[0:7];
  reg [31:0] memory[0:1023];
  reg frame_start=0,read_phase=0;
  wire pixel_valid,underflow;
  wire [23:0] pixel_rgb;
  wire [7:0] reader_error;
  integer pixels=0,j;
  media_frame_reader #(.IMAGE_WORDS(512)) reader(
    .mem_clk(clk),.mem_rst_n(rst_n),.controller_init_done(rst_n),
    .controller_busy(refresh_active),.refresh_active(hold_new || refresh_active),
    .app_rd_en(actual_rd_en),.app_rd_addr(actual_rd_addr),
    .sdram_rd_valid(rd_pipe[7]),.sdram_rd_data(data_pipe[7]),
    .wr_burst_active(wr_active),.rd_burst_active(actual_rd_active),
    .pix_clk(pix_clk),.pix_rst_n(rst_n),.frame_start(frame_start),
    .active_index(2'd0),.thumb_mode(1'b0),.thumb_mode_frame(),
    .pixel_consume(read_phase && pixel_valid),.pixel_rgb(pixel_rgb),
    .pixel_valid(pixel_valid),.underflow(underflow),.reader_busy(),
    .frame_read_done(),.reader_index(),.reader_error(reader_error));
  always @(posedge clk) begin
    rd_pipe<={rd_pipe[6:0],actual_rd_en};
    if(actual_rd_en) data_pipe[0]<=memory[actual_rd_addr];
    for(j=1;j<8;j=j+1) data_pipe[j]<=data_pipe[j-1];
    if(req && rd_pipe!=0) $fatal(1,"refresh started with read returns still in flight");
  end
  always @(posedge pix_clk) if(read_phase && pixel_valid) begin
    if(pixel_rgb !== (24'haaaa55 ^ pixels)) $fatal(1,"read pixel mismatch at %0d: %h",pixels,pixel_rgb);
    pixels=pixels+1;
  end
  integer read_cycles=0,delay_count=0,refresh_cycles=0;
  integer seen=0,requests=0,last_write=0,cycles=0,i;
  reg previous_req=0;
  sdram_refresh_guard #(.INTERVAL_CYCLES(100),.QUIET_CYCLES(8),.TIMEOUT_CYCLES(512)) guard(
    .clk(clk),.rst_n(rst_n),.init_done(rst_n),.rd_active(rd_active),
    .wr_active(wr_active),.app_rd_en(rd_en),.app_wr_en(wr_en),
    .refresh_active(refresh_active),.hold_new_bursts(hold_new),.app_ref_req(req),.fault(fault));
  media_sdram_write_cdc writer(
    .src_clk(src_clk),.src_rst_n(rst_n),.src_wr_en(src_we),
    .src_wr_addr(src_addr),.src_wr_mask(4'd0),.src_wr_data(src_data),
    .src_full(full),.src_overflow(overflow),.dst_clk(clk),.dst_rst_n(rst_n),
    .rd_burst_active(rd_active),.refresh_hold(hold_new),.dst_app_wr_en(wr_en),
    .dst_app_wr_addr(wr_addr),.dst_app_wr_mask(),.dst_app_wr_data(wr_data),
    .wr_burst_active(wr_active),.dst_idle(idle));

  // A read already in flight must finish even after the refresh hold rises.
  always @(negedge clk) if(rst_n) begin
    if(read_cycles<180) begin manual_rd_active=1; manual_rd_en=read_cycles<160; read_cycles=read_cycles+1; end
    else begin manual_rd_active=0; manual_rd_en=0; end
  end
  // Behavioral controller handshake: delayed acceptance, 20-cycle refresh.
  always @(posedge clk) if(rst_n) begin
    cycles=cycles+1;
    if(fault || overflow) $fatal(1,"arbiter fault or source overflow");
    if(req) begin
      if(previous_req || rd_active || wr_active || wr_en || rd_en || refresh_active)
        $fatal(1,"refresh overlaps a transfer or request is not a pulse");
      if(cycles-last_write<8) $fatal(1,"write pipeline did not drain");
      requests=requests+1; delay_count=4;
    end else if(delay_count>0) begin
      delay_count=delay_count-1;
      if(delay_count==0) begin refresh_active<=1; refresh_cycles=20; end
    end else if(refresh_cycles>0) begin
      refresh_cycles=refresh_cycles-1;
      if(refresh_cycles==0) refresh_active<=0;
    end
    previous_req=req;
    if(refresh_active && (wr_en || rd_en)) $fatal(1,"memory traffic during refresh");
    if(wr_en) begin
      if(wr_addr!==seen || wr_data!==(seen^32'h55aaaa55))
        $fatal(1,"lost/reordered command %0d addr=%0d data=%h",seen,wr_addr,wr_data);
      seen=seen+1; last_write=cycles;
      memory[wr_addr]=wr_data;
    end
  end

  // A controller that never acknowledges refresh must produce a sticky fault.
  wire timeout_fault,timeout_hold;
  sdram_refresh_guard #(.INTERVAL_CYCLES(20),.QUIET_CYCLES(4),.TIMEOUT_CYCLES(32)) no_ack(
    .clk(clk),.rst_n(rst_n),.init_done(rst_n),.rd_active(1'b0),.wr_active(1'b0),
    .app_rd_en(1'b0),.app_wr_en(1'b0),.refresh_active(1'b0),
    .hold_new_bursts(timeout_hold),.app_ref_req(),.fault(timeout_fault));
  initial begin
    repeat(8) @(negedge src_clk); rst_n=1;
    for(i=0;i<1024;i=i+1) begin
      while(full) begin src_we=0; @(negedge src_clk); end
      src_we=1; src_addr=i; src_data=i^32'h55aaaa55;
      @(negedge src_clk);
    end
    src_we=0;
    wait(seen==1024 && idle && requests>=4);
    @(negedge pix_clk); read_phase=1; frame_start=1;
    @(negedge pix_clk); frame_start=0;
    wait(pixels==512);
    @(negedge pix_clk); read_phase=0;
    repeat(10) @(negedge clk);
    if(reader_error!=0 || underflow) $fatal(1,"reader failed error=%h underflow=%b",reader_error,underflow);
    if(!timeout_fault || !timeout_hold) $fatal(1,"missing controller timeout diagnosis");
    $display("PASS refresh arbitration: 1024 CDC writes, 512 ordered pixels, %0d refreshes, drain, queue recovery and timeout",requests);
    $finish;
  end
  initial begin #2000000; $fatal(1,"arbiter stalled"); end
endmodule
