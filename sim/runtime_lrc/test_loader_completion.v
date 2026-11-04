`timescale 1ns/1ps
module test_loader_completion;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,load_start=0,pixel_valid=0,frame_commit=0;
 reg cache_invalidate=0,keep_valid=0;reg [1:0] keep_slot=0;
 reg [23:0] pixel_rgb=0;
 reg [7:0] decode_error=0;
 wire busy,done,we; wire [3:0] complete,mask;
 wire [7:0] error; wire [20:0] addr; wire [31:0] data;
 integer written=0,done_seen=0,i;
 media_frame_loader #(.IMAGE_WORDS(32),.FIFO_DEPTH(16),.BURST_SIZE(8),.WRITE_V_FLIP(0)) dut(
 .clk(clk),.rst_n(rst_n),.load_start(load_start),.menu_load(1'b0),.image_index(2'd1),
 .cache_invalidate(cache_invalidate),.keep_valid(keep_valid),.keep_slot(keep_slot),
 .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.frame_commit(frame_commit),.decode_error(decode_error),
 .load_busy(busy),.load_done(done),.image_complete(complete),.memory_error(error),
 .controller_init_done(rst_n),.controller_busy(1'b0),.refresh_active(1'b0),
 .app_wr_en(we),.app_wr_addr(addr),.app_wr_mask(mask),.app_wr_data(data));
 always @(posedge clk) if(rst_n) begin
  if(we)begin
   if(addr!==32+written || data!==written || mask!==0)$fatal(1,"ordered loader write mismatch");
   written=written+1;
  end
  if(done)done_seen=done_seen+1;
 end
 task transfer;
 input integer count; input [7:0] expected_error;
 begin
  @(negedge clk);rst_n=0;load_start=0;pixel_valid=0;frame_commit=0;
  repeat(3)@(negedge clk);
  written=0;done_seen=0;rst_n=1;
  @(negedge clk);load_start=1;@(negedge clk);load_start=0;
  for(i=0;i<count;i=i+1)begin pixel_valid=1;pixel_rgb=i;@(negedge clk);end
  pixel_valid=0;frame_commit=1;@(negedge clk);frame_commit=0;
  wait(done_seen!=0);@(negedge clk);
  if(error!==expected_error || busy || done_seen!=1)$fatal(1,"loader completion/error mismatch count=%0d err=%h",count,error);
  if(expected_error==0)begin
   if(complete!==2 || written!=32)$fatal(1,"successful completion before exact final write");
  end else if(complete!==0)$fatal(1,"invalid frame marked complete");
  repeat(8)@(negedge clk);
  if(done_seen!=1)$fatal(1,"repeated completion pulse");
 end
 endtask
 task inv_check;
  input keep_v;input [1:0] keep_s;input [3:0] expected;
  begin
   @(negedge clk);cache_invalidate=1;keep_valid=keep_v;keep_slot=keep_s;
   @(negedge clk);cache_invalidate=0;keep_valid=0;@(negedge clk);
   if(complete!==expected)$fatal(1,"invalidate keep semantics wrong: complete=%b expected=%b",complete,expected);
  end
 endtask
 initial begin
  transfer(0,8'h45);transfer(31,8'h45);transfer(32,0);transfer(33,8'h43);transfer(32,0);
  // 页失效软清：无keep全清；keep当前显示槽（=image_index 1）则保留，keep他槽不保留
  inv_check(0,2'd0,4'b0000);
  transfer(32,0);
  inv_check(1,2'd1,4'b0010);
  inv_check(1,2'd2,4'b0000);
  $display("PASS loader completion: empty/short/exact/oversized frames, final write, single done, recovery, invalidate keep semantics");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
