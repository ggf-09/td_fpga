`timescale 1ns/1ps
module test_checkpoint;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,catalog_done=0,snapshot_valid=0;
 reg [1:0] slots_valid=3;reg [7:0] spc=1;
 reg [3:0] snapshot_track=12;
 reg [31:0] snapshot_frame=480000;
 wire boot_ready,restore_valid,enabled,save_error,want_bus,read_req,write_req;
 wire [3:0] restore_track;wire [31:0] restore_frame,restore_size,restore_cluster,read_lba,write_lba;
 wire [7:0] write_byte;
 reg read_valid=0,read_done=0,write_next=0,write_done=0,write_error=0;
 reg [7:0] read_byte=0;reg [8:0] read_index=0;
 reg [7:0] read_error=0;
 playback_checkpoint #(.SAVE_FRAME_SHIFT(17)) dut(
 .clk(clk),.rst_n(rst_n),.catalog_done(catalog_done),.slots_valid(slots_valid),
 .cluster_a(32'd10),.cluster_b(32'd20),.data_start(32'd100),.max_cluster(32'd1000),.spc(spc),
 .snapshot_valid(snapshot_valid),.snapshot_track(snapshot_track),.snapshot_frame(snapshot_frame),
 .snapshot_size(32'd4000044),.snapshot_cluster(32'd30),
 .boot_ready(boot_ready),.restore_valid(restore_valid),.restore_track(restore_track),
 .restore_frame(restore_frame),.restore_size(restore_size),.restore_cluster(restore_cluster),
 .enabled(enabled),.save_error(save_error),.want_bus(want_bus),.bus_granted(want_bus),
 .read_req(read_req),.read_lba(read_lba),.read_valid(read_valid),.read_byte(read_byte),
 .read_index(read_index),.read_done(read_done),.read_error(read_error),
 .write_req(write_req),.write_lba(write_lba),.write_byte(write_byte),
 .write_next(write_next),.write_done(write_done),.write_error(write_error));
 reg [7:0] disk[0:1023];integer i,j,base,writes=0,cut=-1,byte_gap=9;reg active=0;
 // Model one-cycle byte request followed by consumption, as in sd_card_cmd.
 initial forever begin
  @(negedge clk);
  if(rst_n && read_req)begin
   base=read_lba==100+8*spc?0:read_lba==100+18*spc?512:-1;if(base<0)$fatal(1,"unsafe read LBA");
   for(j=0;j<512 && rst_n;j=j+1)begin
    read_valid=1;read_index=j;read_byte=disk[base+j];@(negedge clk);read_valid=0;repeat(byte_gap)@(negedge clk);
   end
   read_valid=0;if(rst_n)read_done=1;@(negedge clk);read_done=0;
  end else if(rst_n && write_req)begin
   base=write_lba==100+8*spc?0:write_lba==100+18*spc?512:-1;if(base<0)$fatal(1,"unsafe write LBA");
   active=1;
   for(j=0;j<512 && rst_n;j=j+1)begin
    write_next=1;@(negedge clk);write_next=0;
    disk[base+j]=write_byte;@(negedge clk);
    if(j==cut)begin rst_n=0;snapshot_valid=0;end
   end
   active=0;
   if(rst_n)begin write_done=1;writes=writes+1;end
   @(negedge clk);write_done=0;
  end
 end
 task boot;
 begin
  rst_n=0;snapshot_valid=0;repeat(5)@(negedge clk);
  rst_n=1;catalog_done=1;@(negedge clk);catalog_done=0;
  wait(boot_ready);repeat(3)@(negedge clk);
 end endtask
 initial begin
  for(i=0;i<1024;i=i+1)disk[i]=0;
  boot();if(restore_valid || !enabled)$fatal(1,"blank boot");
  snapshot_valid=1;wait(writes==1);wait(!want_bus);snapshot_valid=0;
  if(save_error)$fatal(1,"write/verify failed");
  $writememh("checkpoint_saved.hex",disk);
  snapshot_frame=480001;snapshot_valid=1;repeat(1200)@(negedge clk);snapshot_valid=0;
  if(writes!=1)$fatal(1,"same position segment was written repeatedly");snapshot_frame=480000;
  boot();if(!restore_valid || restore_track!=12 || restore_frame!=480000)$fatal(1,"restore A");
  snapshot_frame=620000;snapshot_valid=1;wait(writes==2);wait(!want_bus);snapshot_valid=0;
  boot();if(restore_frame!=620000)$fatal(1,"latest B");
  // Power loss while overwriting A, before the checksum has been written.
  cut=18;snapshot_frame=720000;snapshot_valid=1;wait(!rst_n);repeat(5)@(negedge clk);cut=-1;
  boot();if(!restore_valid || restore_frame!=620000)$fatal(1,"torn A lost previous B");
  disk[512+14]=disk[512+14]^8'h80;
  boot();if(restore_valid)$fatal(1,"corrupt records accepted");
  write_error=1;snapshot_frame=800000;snapshot_valid=1;wait(writes==3);wait(!want_bus);snapshot_valid=0;
  if(enabled || !save_error)$fatal(1,"write failure kept saving");write_error=0;
  slots_valid=1;boot();if(enabled || restore_valid)$fatal(1,"missing slot enabled writes");
  slots_valid=3;read_error=8'h10;boot();if(enabled || !save_error)$fatal(1,"read error enabled writes");
  read_error=0;slots_valid=3;$readmemh("checkpoint_wrap.hex",disk);
  for(i=1;i<=128;i=i*2)begin spc=i;boot();if(!restore_valid || restore_frame!=620000)$fatal(1,"generation wrap / cluster geometry");end
  // Consecutive successful saves cross the wrap in real write/readback paths.
  for(i=4;i<=8;i=i+1)begin
   snapshot_frame=100000+(i-4)*131072;snapshot_valid=1;
   wait(writes==i);wait(!want_bus);snapshot_valid=0;
   boot();if(!restore_valid || restore_frame!=snapshot_frame)$fatal(1,"consecutive save across wrap");
  end
  // Reject an EOF/out-of-range snapshot before any card write, then recover
  // even when the next valid position is in the previously saved segment.
  snapshot_frame=1000000;snapshot_valid=1;repeat(1200)@(negedge clk);
  if(writes!=8)$fatal(1,"invalid frame reached SD write");
  snapshot_frame=624289;wait(writes==9);wait(!want_bus);snapshot_valid=0;
  boot();if(restore_frame!=624289)$fatal(1,"valid snapshot after rejected frame lost");
  // A future burst interface must not silently accept unsupported byte pacing.
  byte_gap=0;boot();if(restore_valid || enabled || !save_error)$fatal(1,"fast input accepted");byte_gap=9;
  spc=3;boot();if(enabled)$fatal(1,"invalid geometry enabled");
  $display("PASS checkpoint: blank boot, alternating slots, write/readback, latest record, torn write, CRC rejection, missing files and read failure");$finish;
 end
 initial begin #10000000;$fatal(1,"checkpoint timeout state=%d",dut.state);end
endmodule
