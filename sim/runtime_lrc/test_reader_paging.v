`timescale 1ns/1ps
module test_reader_paging;
 reg mem_clk=0;always #4 mem_clk=~mem_clk;
 reg pix_clk=0;always #20 pix_clk=~pix_clk;
 reg rst_n=0,frame_start=0,frame_enable=0,pixel_consume=0;
 reg [1:0] active_index=0;
 wire app_rd_en,rd_burst_active,pixel_valid,underflow,frame_read_done;
 wire [20:0] app_rd_addr;
 wire [23:0] pixel_rgb;
 wire [7:0] reader_error;
 reg [7:0] return_pipe=0;
 reg [31:0] data_pipe[0:7];
 reg [7:0] generation=0;
 integer j,pixels=0,phase=0;
 reg old_toggle;
 media_frame_reader #(.IMAGE_WORDS(512),.FRAME_ENABLE_CONTROL(1)) dut(
 .mem_clk(mem_clk),.mem_rst_n(rst_n),.controller_init_done(rst_n),
 .controller_busy(1'b0),.refresh_active(1'b0),.app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),
 .sdram_rd_valid(return_pipe[7]),.sdram_rd_data(data_pipe[7]),.wr_burst_active(1'b0),.rd_burst_active(rd_burst_active),
 .pix_clk(pix_clk),.pix_rst_n(rst_n),.frame_start(frame_start),.frame_enable(frame_enable),
 .active_index(active_index),.thumb_mode(1'b0),.thumb_mode_frame(),.pixel_consume(pixel_consume),
 .pixel_rgb(pixel_rgb),.pixel_valid(pixel_valid),.underflow(underflow),.reader_busy(),
 .frame_read_done(frame_read_done),.reader_index(),.reader_error(reader_error));
 always @(posedge mem_clk)begin
  return_pipe<={return_pipe[6:0],app_rd_en};
  if(app_rd_en)data_pipe[0]<={8'd0,generation,16'd0}+app_rd_addr;
  for(j=1;j<8;j=j+1)data_pipe[j]<=data_pipe[j-1];
 end
 always @(posedge pix_clk)if(pixel_consume&&pixel_valid&&frame_enable)begin
  if(phase==1 && pixel_rgb!==(24'h010200+pixels))$fatal(1,"old page pixels survived reload at %0d: %h",pixels,pixel_rgb);
  pixels=pixels+1;
 end
 task frame;
 begin @(negedge pix_clk);frame_start=1;@(negedge pix_clk);frame_start=0;end
 endtask
 initial begin
  repeat(6)@(negedge pix_clk);rst_n=1;frame_enable=1;frame();
  repeat(200)@(negedge pix_clk);pixel_consume=1;
  wait(pixels==200);@(negedge pix_clk);pixel_consume=0;frame_enable=0;
  repeat(4)@(negedge pix_clk);old_toggle=dut.request_toggle_pix;
  repeat(3)begin
   frame();repeat(100)@(negedge pix_clk);
   if(underflow||dut.frame_armed_pix||dut.request_toggle_pix!=old_toggle)
    $fatal(1,"intentional page-load pause counted as an incomplete frame or new request");
  end
  active_index=1;generation=1;phase=1;pixels=0;
  // The top enables pixel consumption only at the frame whose new request
  // is issued. The vertical blanking interval permits FIFO drain/reset.
  frame_enable=1;frame();repeat(200)@(negedge pix_clk);
  pixel_consume=1;wait(pixels==512);@(negedge pix_clk);pixel_consume=0;
  if(underflow||reader_error!=0)$fatal(1,"page resume falsely reported underflow/error");
  frame();repeat(4)@(negedge pix_clk);
  if(underflow)$fatal(1,"resumed full frame had wrong consumption count");
  $display("PASS actual reader page pause/resume: partial old frame canceled, no false underflow, 512 ordered fresh pixels");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
