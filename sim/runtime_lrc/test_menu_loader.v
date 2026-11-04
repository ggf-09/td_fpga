`timescale 1ns/1ps
module test_menu_loader;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,load_start=0,pixel_valid=0,frame_commit=0,menu_load=0;
 reg [1:0] image_index=2;
 reg [23:0] pixel_rgb=0;
 wire load_done,load_busy,app_wr_en;wire [3:0] image_complete;wire [7:0] memory_error;
 wire [20:0] app_wr_addr;wire [31:0] app_wr_data;wire [3:0] app_wr_mask;
 integer i,phase=0,written=0,expected;
 media_frame_loader #(.IMAGE_WORDS(32),.FIFO_DEPTH(16),.BURST_SIZE(8),.FRAME_WIDTH(8),.FRAME_HEIGHT(4),.MENU_SUPPORT(1)) dut(
 .clk(clk),.rst_n(rst_n),.load_start(load_start),.image_index(image_index),.menu_load(menu_load),
 .cache_invalidate(1'b0),.keep_valid(1'b0),.keep_slot(2'd0),
 .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.frame_commit(frame_commit),.decode_error(8'd0),
 .load_busy(load_busy),.load_done(load_done),.image_complete(image_complete),.memory_error(memory_error),
 .controller_init_done(rst_n),.controller_busy(1'b0),.refresh_active(1'b0),
 .app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),.app_wr_mask(app_wr_mask),.app_wr_data(app_wr_data));
 always @(posedge clk)if(app_wr_en)begin
  expected=(phase==0?64:128)+(3-written/8)*8+written%8;
  if(app_wr_addr!==expected||app_wr_data!==written)$fatal(1,"loader menu address/data error");
  if(phase==1&&(app_wr_addr<128||app_wr_addr>=160))$fatal(1,"menu overwrote cover banks");
  written=written+1;
 end
 task transfer;
 begin
  @(negedge clk);load_start=1;@(negedge clk);load_start=0;
  for(i=0;i<32;i=i+1)begin pixel_valid=1;pixel_rgb=i;@(negedge clk);end
  pixel_valid=0;frame_commit=1;@(negedge clk);frame_commit=0;
  wait(load_done);@(negedge clk);
  if(memory_error||written!=32)$fatal(1,"load failed");
 end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;transfer();
  if(image_complete!=4)$fatal(1,"normal cover flag missing");
  phase=1;written=0;menu_load=1;image_index=0;transfer();
  if(image_complete!=4)$fatal(1,"menu changed cover validity");
  $display("PASS menu loader: reserved bank, all reversed rows/ordered RGB, original cover flags retained");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
