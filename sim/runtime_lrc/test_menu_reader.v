`timescale 1ns/1ps
module test_menu_reader;
 reg mem_clk=0;always #4 mem_clk=~mem_clk;
 reg pix_clk=0;always #20 pix_clk=~pix_clk;
 reg rst_n=0,frame_start=0,pixel_consume=0,menu_ready=1;
 reg [1:0] menu_page=0;
 wire app_rd_en,pixel_valid,underflow,rd_burst_active,frame_read_done;
 wire [20:0] app_rd_addr;wire [23:0] pixel_rgb;wire [7:0] reader_error;
 wire menu_mode_frame;wire [1:0] menu_page_frame;
 reg [7:0] ret=0;reg [31:0] data[0:7];
 integer j,read_count=0,pixel_count=0,phase=0,row,col,y,x,p,expected;
 reg [20:0] last_addr;
 media_frame_reader #(.MENU_SUPPORT(1)) dut(
 .mem_clk(mem_clk),.mem_rst_n(rst_n),.controller_init_done(rst_n),.controller_busy(1'b0),.refresh_active(1'b0),
 .app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),.sdram_rd_valid(ret[7]),.sdram_rd_data(data[7]),
 .wr_burst_active(1'b0),.rd_burst_active(rd_burst_active),
 .pix_clk(pix_clk),.pix_rst_n(rst_n),.frame_start(frame_start),.frame_enable(1'b1),.active_index(2'd0),
 .thumb_mode(1'b1),.thumb_mode_frame(),.menu_ready(menu_ready),.menu_page(menu_page),
 .menu_mode_frame(menu_mode_frame),.menu_page_frame(menu_page_frame),
 .pixel_consume(pixel_consume),.pixel_rgb(pixel_rgb),.pixel_valid(pixel_valid),.underflow(underflow),
 .reader_busy(),.frame_read_done(frame_read_done),.reader_index(),.reader_error(reader_error));
 always @(posedge mem_clk)begin
  ret<={ret[6:0],app_rd_en};
  if(app_rd_en)begin
   data[0]<={11'd0,app_rd_addr};
   if(phase<4)begin
    row=read_count/640;col=read_count%640;
    expected=1228800+phase*76800+(row%120)*640+col;
    if(app_rd_addr!==expected)$fatal(1,"menu read addr page=%0d word=%0d got=%0d exp=%0d",phase,read_count,app_rd_addr,expected);
   end
   if(read_count%128!=0 && app_rd_addr!=last_addr+1)$fatal(1,"nonsequential read within a burst");
   last_addr=app_rd_addr;read_count=read_count+1;
  end
  for(j=1;j<8;j=j+1)data[j]<=data[j-1];
 end
 always @(posedge pix_clk)if(pixel_consume)begin
  if(!pixel_valid)$fatal(1,"menu pixel underflow");
  row=pixel_count/320;col=pixel_count%320;
  if(phase<4)expected=1228800+phase*76800+(row%120)*640+(row>=120?320:0)+col;
  else expected=((row>=120?2:0)+(col>=160?1:0))*307200+(row%120)*2560+(col%160)*4;
  if(pixel_rgb!==expected)$fatal(1,"pixel ordering phase=%0d n=%0d got=%h exp=%h",phase,pixel_count,pixel_rgb,expected);
  pixel_count=pixel_count+1;
 end
 task frame;
 begin @(negedge pix_clk);frame_start=1;@(negedge pix_clk);frame_start=0;end
 endtask
 initial begin
  repeat(6)@(negedge pix_clk);rst_n=1;
  for(p=0;p<5;p=p+1)begin
   phase=p;menu_page=p;menu_ready=p<4;read_count=0;pixel_count=0;
   frame();repeat(2000)@(negedge pix_clk);
   if(menu_mode_frame!==(p<4)||menu_page_frame!==p%4)$fatal(1,"menu frame snapshot mismatch");
   for(y=0;y<240;y=y+1)begin
    pixel_consume=1;repeat(320)@(negedge pix_clk);pixel_consume=0;
    repeat(480)@(negedge pix_clk);
   end
   repeat(20)@(negedge pix_clk);
   if(pixel_count!=76800||read_count!=(p<4?153600:307200)||underflow||reader_error!=0)
    $fatal(1,"frame accounting phase=%0d pixels=%0d reads=%0d error=%h",p,pixel_count,read_count,reader_error);
  end
  $display("PASS actual reader: all pixels of four menu pages, 128-word sequential bursts, no underflow, legacy four-cover stride fallback");$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
