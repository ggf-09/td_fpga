`timescale 1ns/1ps
module test_menu_boot;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,sd_init_done=0,cache_invalidate=0,scan_done_latched=0;
 reg [3:0] scan_valid_latched=15;reg scanner_menu_valid=1;
 reg [31:0] scanner_menu_cluster=901,scanner_menu_size=921654;
 reg loader_load_done=0;reg [7:0] loader_memory_error=0;
 reg streamer_file_done=0;reg [7:0] streamer_fs_error=0;reg streamer_byte_valid=0;
 reg [1:0] requested_slot=0;
 wire decoder_scale_complete=1,decoder_header_error=0,decoder_dims_valid=1;
 wire [15:0] decoder_width_bcd=16'h0640,decoder_height_bcd=16'h0480;
 wire load_abort,frame_commit;wire [7:0] decode_error;
 wire menu_ready,load_menu,load_start,sd_free;wire [1:0] load_image_index;wire [31:0] load_cluster,load_file_size;
 integer covers=0,menus=0,phase=0;
 reg [1:0] exp_slot;
 menu_boot_fragment dut(.*);
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 initial forever begin
  @(negedge clk);
  if(load_start)begin
   if(load_menu)begin
    menus=menus+1;
    if(load_cluster!=901||load_file_size!=921654)$fatal(1,"wrong menu descriptor");
   end else begin
    exp_slot=(covers%4+requested_slot)%4;
    if(load_image_index!==exp_slot||load_cluster!==100+exp_slot)$fatal(1,"wrong cover order");
    covers=covers+1;
   end
   tick(4);loader_memory_error=phase==3&&load_menu?8'h45:0;
   loader_load_done=1;tick(1);loader_load_done=0;
  end
 end
 initial begin
  tick(3);rst=0;tick(2);sd_init_done=1;scan_done_latched=1;
  wait(sd_free);tick(2);
  if(covers!=4||menus!=1||!menu_ready)$fatal(1,"boot preload failed");
  phase=1;scan_done_latched=0;cache_invalidate=1;tick(2);cache_invalidate=0;tick(4);scan_done_latched=1;
  wait(sd_free);tick(2);
  if(covers!=8||menus!=1||!menu_ready)$fatal(1,"cache reload invalidated/reloaded atlas");
  // Missing atlas permits ordinary four-cover playback.
  phase=2;sd_init_done=0;tick(3);covers=0;menus=0;scanner_menu_valid=0;sd_init_done=1;
  wait(sd_free);tick(2);if(covers!=4||menus!=0||menu_ready)$fatal(1,"missing-atlas boot blocked");
  // A damaged atlas retries once, then yields the SD card to music.
  phase=3;sd_init_done=0;tick(3);covers=0;menus=0;scanner_menu_valid=1;sd_init_done=1;
  wait(sd_free);tick(2);if(covers!=4||menus!=2||menu_ready)$fatal(1,"bad-atlas retry did not terminate");
  // Priority reload: requested_slot=2 rotates the cover order to 2,3,0,1.
  phase=4;requested_slot=2;covers=0;scan_done_latched=0;
  cache_invalidate=1;tick(2);cache_invalidate=0;tick(4);scan_done_latched=1;
  wait(sd_free);tick(2);
  if(covers!=4||menus!=2)$fatal(1,"priority-slot reload order wrong");
  $display("PASS actual boot FSM: four covers then atlas once, cache reload preserves atlas, missing/bad atlas yields SD card, one retry, priority slot rotates cover order");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
