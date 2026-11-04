`timescale 1ns/1ps
// FIFO capacity and ordering under long consumer stalls, delayed occupancy
// reporting, two bursts in flight and independently stalled SDRAM returns.
module test_reader_reservation;
 reg mem_clk=0,pix_clk=0,rst_n=0,frame_start=0,pixel_consume=0;
 always #4 mem_clk=~mem_clk;always #20 pix_clk=~pix_clk;
 reg [1:0] active_index=0;
 wire app_rd_en,pixel_valid,underflow,reader_busy,frame_read_done;
 wire [20:0] app_rd_addr;
 wire [23:0] pixel_rgb;
 wire [7:0] reader_error;
 reg sdram_valid=0;reg [31:0] sdram_data=0;
 reg [20:0] queue[0:511];integer due[0:511];
 integer wp=0,rp=0,cycle=0,phase=0,latency=0,reads=0,pixels=0,peak=0;
 reg [15:0] random_state=16'hd035;
 media_frame_reader #(.IMAGE_WORDS(4096)) dut(
  .mem_clk(mem_clk),.mem_rst_n(rst_n),.controller_init_done(rst_n),
  .controller_busy(1'b0),.refresh_active(1'b0),.wr_burst_active(1'b0),.rd_burst_active(),
  .app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),.sdram_rd_valid(sdram_valid),.sdram_rd_data(sdram_data),
  .pix_clk(pix_clk),.pix_rst_n(rst_n),.frame_start(frame_start),.frame_enable(1'b1),
  .active_index(active_index),.menu_ready(1'b0),.menu_page(2'b0),.menu_mode_frame(),.menu_page_frame(),
  .thumb_mode(1'b0),.thumb_mode_frame(),.pixel_consume(pixel_consume),.pixel_rgb(pixel_rgb),.pixel_valid(pixel_valid),
  .underflow(underflow),.reader_busy(reader_busy),.frame_read_done(frame_read_done),.reader_index(),.reader_error(reader_error));
 always @(negedge mem_clk)if(rst_n)begin
  cycle=cycle+1;
  random_state={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
  if(app_rd_en)begin
   if(app_rd_addr!=phase*4096+reads)$fatal(1,"reservation issued wrong source address");
   queue[wp%512]=app_rd_addr;due[wp%512]=cycle+8+latency;wp=wp+1;reads=reads+1;
  end
  sdram_valid=0;
  if(wp>rp && due[rp%512]<=cycle && random_state[2:0]!=0)begin
   sdram_data={11'd0,queue[rp%512]};rp=rp+1;sdram_valid=1;
  end
  if(dut.u_read_fifo.used>peak)peak=dut.u_read_fifo.used;
  if(dut.u_read_fifo.used+dut.inflight_count_mem>512)$fatal(1,"reserved beyond physical FIFO capacity");
  if(dut.fifo_write_enable && dut.fifo_full)$fatal(1,"reservation permitted write into full FIFO");
 end
 always @(posedge pix_clk)begin
  if(rst_n && pixel_consume)begin
   if(!pixel_valid || pixel_rgb!==phase*4096+pixels)$fatal(1,"stalled consumer pixel mismatch phase%0d n%0d got%h valid%b expected%h",phase,pixels,pixel_rgb,pixel_valid,phase*4096+pixels);
   pixels=pixels+1;
  end
 end
 always @(negedge pix_clk)begin
  pixel_consume=rst_n && pixels<4096 && pixel_valid && cycle%7000>=2500 && random_state[1];
 end
 integer p;
 initial begin
  repeat(6)@(negedge pix_clk);rst_n=1;
  for(p=0;p<3;p=p+1)begin
   phase=p;active_index=p;latency=p==0?0:p==1?200:2000;
   reads=0;pixels=0;wp=0;rp=0;cycle=0;peak=0;
   @(negedge pix_clk);frame_start=1;@(negedge pix_clk);frame_start=0;
   wait(pixels==4096);@(negedge pix_clk);pixel_consume=0;
   repeat(20)@(negedge pix_clk);
   if(reads!=4096 || rp!=wp || reader_busy || underflow || reader_error!=0 || peak<370)
    $fatal(1,"reservation phase%0d incomplete: reads%0d peak%0d err%h",p,reads,peak,reader_error);
  end
  $display("PASS reader reservation: 12288 ordered pixels, long consumer stalls, 8/208/2008-cycle return delays, one-clock occupancy lag, two bursts in flight and no capacity overrun");$finish;
 end
 initial begin #20000000;$fatal(1,"reservation stress timeout");end
endmodule
