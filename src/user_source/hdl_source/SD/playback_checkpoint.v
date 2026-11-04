`timescale 1ns/1ps
// Preallocated RESUMA.BIN / RESUMB.BIN. LE: RSM1, generation (modulo four),
// track, frame, WAV size, first cluster, IEEE CRC32(first24), inverse CRC.
// Parse incoming bytes directly; share the byte selector, CRC and address ALU.
module playback_checkpoint #(parameter integer SAVE_FRAME_SHIFT=17)(
 input wire clk,rst_n,catalog_done,input wire [1:0] slots_valid,
 input wire [31:0] cluster_a,cluster_b,data_start,max_cluster,input wire [7:0] spc,
 input wire snapshot_valid,input wire [3:0] snapshot_track,
 input wire [31:0] snapshot_frame,snapshot_size,snapshot_cluster,
 output reg boot_ready,restore_valid,output reg [3:0] restore_track,
 output reg [31:0] restore_frame,restore_size,restore_cluster,
 output reg enabled,save_error,output wire want_bus,input wire bus_granted,
 output reg read_req,output wire [31:0] read_lba,
 input wire read_valid,input wire [7:0] read_byte,input wire [8:0] read_index,
 input wire read_done,input wire [7:0] read_error,
 output wire write_req,output wire [31:0] write_lba,
 output reg [7:0] write_byte,input wire write_next,write_done,write_error
);
 localparam WAIT_CATALOG=0,SUBTRACT=1,SHIFT=2,ADD=3,LOAD_B=4,BOOT_A=5,
 READ_ISSUE=6,READ_WAIT=7,CHECK=8,IDLE=9,BUILD=10,WRITE_WAIT=11,
 VERIFY_ISSUE=12,VERIFY_WAIT=13,VERIFY_CHECK=14,COPY_ISSUE=15,COPY_APPLY=16,FINISH_CHECK=17,
 SNAP_LIMIT=18,SNAP_COMPARE=19,SNAP_CHECK=20;
 reg [4:0] state;
 reg [31:0] address_work;
 // Slot addresses are recomputed in this shared register before each access.
 reg address_write;
 reg [2:0] shifts_left;
 reg slot,latest_slot,have_latest;
 reg frame_hi_lt,frame_hi_eq,frame_lo_lt,force_save;
 reg [1:0] generation,rx_generation;
 wire [1:0] next_generation=generation+2'd1,age=rx_generation-generation;
 reg [31:0] crc;
 reg [3:0] crc_bits;
 reg [3:0] rx_track;
 wire receiving=state==READ_WAIT || state==VERIFY_WAIT;
 // Only a small synchronous RAM holds the unvalidated candidate metadata.
 // It never overwrites the selected valid record before its CRC has passed.
 reg [7:0] candidate [0:511] /* fehdl force_ram=1, ram_style="bram" */;
 reg [7:0] candidate_q;
 reg [3:0] copy_index;
 always @(posedge clk)begin
  if(receiving && read_valid && read_index>=12 && read_index<24)
   candidate[{5'd0,read_index[3:0]}]<=read_byte;
  candidate_q<=candidate[{5'd0,copy_index}];
 end
 reg [4:0] build_index;
 reg [9:0] tx_index,rx_count;
 reg io_failed,boot_read_failed,header_bad,crc_bad,verify_bad;
 wire [4:0] record_index=state==BUILD?build_index:receiving?read_index[4:0]:tx_index[4:0];
 reg [7:0] record_byte;
 always @* begin
  case(record_index)
   5'd0:record_byte=8'h52;
   5'd1:record_byte=8'h53;
   5'd2:record_byte=8'h4d;
   5'd3:record_byte=8'h31;
   5'd4:record_byte={6'd0,next_generation};
   5'd8:record_byte={4'd0,restore_track};
   5'd12:record_byte=restore_frame[7:0];
   5'd13:record_byte=restore_frame[15:8];
   5'd14:record_byte=restore_frame[23:16];
   5'd15:record_byte=restore_frame[31:24];
   5'd16:record_byte=restore_size[7:0];
   5'd17:record_byte=restore_size[15:8];
   5'd18:record_byte=restore_size[23:16];
   5'd19:record_byte=restore_size[31:24];
   5'd20:record_byte=restore_cluster[7:0];
   5'd21:record_byte=restore_cluster[15:8];
   5'd22:record_byte=restore_cluster[23:16];
   5'd23:record_byte=restore_cluster[31:24];
   5'd24:record_byte=~crc[7:0];
   5'd25:record_byte=~crc[15:8];
   5'd26:record_byte=~crc[23:16];
   5'd27:record_byte=~crc[31:24];
   5'd28:record_byte=crc[7:0];
   5'd29:record_byte=crc[15:8];
   5'd30:record_byte=crc[23:16];
   5'd31:record_byte=crc[31:24];
   default:record_byte=0;
  endcase
 end

 // Top checks descriptor and frame against the actual scanned WAV before use.
 wire record_ok=!io_failed && !header_bad && !crc_bad && rx_count==512;
 wire newer=!have_latest || (age==1);
 // Reuse the absolute PCM position as the save timebase: one segment is
 // 131072 frames / 48000 Hz = 2.7307 s. Pause freezes it; seeks/track changes
 // naturally request a fresh checkpoint. No separate 100 MHz timer is needed.
 wire changed=force_save || !have_latest || snapshot_track!=restore_track ||
  snapshot_frame[31:SAVE_FRAME_SHIFT]!=restore_frame[31:SAVE_FRAME_SHIFT];
 wire [31:0] address_sum=address_work+(state==SUBTRACT?32'hfffffffe:state==SNAP_LIMIT?32'hfffffff5:data_start);
 function [2:0] shift_spc;
  input [7:0] n;begin case(n)
   2:shift_spc=1;4:shift_spc=2;8:shift_spc=3;16:shift_spc=4;
   32:shift_spc=5;64:shift_spc=6;128:shift_spc=7;default:shift_spc=0;
  endcase end
 endfunction
 assign want_bus=state!=WAIT_CATALOG && state!=IDLE;
 assign read_lba=address_work;
 assign write_lba=read_lba;
 assign write_req=state==WRITE_WAIT;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT_CATALOG;boot_ready<=0;restore_valid<=0;restore_track<=0;restore_frame<=0;
   restore_size<=0;restore_cluster<=0;enabled<=0;save_error<=0;
   address_work<=0;address_write<=0;shifts_left<=0;
   slot<=0;latest_slot<=0;have_latest<=0;generation<=0;rx_generation<=0;
   frame_hi_lt<=0;frame_hi_eq<=0;frame_lo_lt<=0;force_save<=0;
   crc<=32'hffffffff;crc_bits<=0;
   rx_track<=0;copy_index<=0;build_index<=0;tx_index<=0;
   rx_count<=0;io_failed<=0;boot_read_failed<=0;header_bad<=0;crc_bad<=0;verify_bad<=0;
   read_req<=0;write_byte<=0;
  end else begin
   read_req<=0;
   if(crc_bits!=0)begin crc<=crc[0]?(crc>>1)^32'hedb88320:crc>>1;crc_bits<=crc_bits-1'b1;end
   if(receiving && read_valid)begin
    if(read_index!=rx_count[8:0] || rx_count>=512)io_failed<=1;
    rx_count<=rx_count+1'b1;
    if(read_index<24)begin
     if(crc_bits!=0)io_failed<=1;
     crc<=crc^{24'd0,read_byte};crc_bits<=8;
    end
    if(read_index<4 && read_byte!=record_byte)header_bad<=1;
    if((read_index>=5 && read_index<=7 || (read_index>=9 && read_index<=11)) && read_byte!=0)header_bad<=1;
    if(read_index==8 && read_byte[7:4]!=0)header_bad<=1;
    if(read_index==4 && read_byte[7:2]!=0)header_bad<=1;
    if(read_index>=24 && read_index<32 && read_byte!=record_byte)crc_bad<=1;
    if(state==VERIFY_WAIT && read_index<24 && read_byte!=record_byte)verify_bad<=1;
    if(read_index==4)rx_generation<=read_byte[1:0];
    if(read_index==8)rx_track<=read_byte[3:0];
   end
   case(state)
    WAIT_CATALOG:if(catalog_done)begin
     // Scanner asserts slots_valid only for in-range, writable, 512-byte files.
     if(slots_valid==3 && cluster_a!=cluster_b && spc!=0 && (spc&(spc-1'b1))==0)begin
      address_work<=cluster_a;slot<=0;address_write<=0;shifts_left<=shift_spc(spc);state<=SUBTRACT;
     end else begin boot_ready<=1;state<=IDLE;end
    end
    SUBTRACT:begin address_work<=address_sum;state<=SHIFT;end
    SHIFT:if(shifts_left!=0)begin address_work<=address_work<<1;shifts_left<=shifts_left-1'b1;end else state<=ADD;
    ADD:begin address_work<=address_sum;state<=address_write?WRITE_WAIT:READ_ISSUE;end
    LOAD_B:begin address_work<=slot?cluster_b:cluster_a;shifts_left<=shift_spc(spc);state<=SUBTRACT;end
    BOOT_A:if(bus_granted)begin slot<=0;state<=READ_ISSUE;end
    READ_ISSUE,VERIFY_ISSUE:if(bus_granted)begin
     read_req<=1;crc<=32'hffffffff;crc_bits<=0;rx_count<=0;io_failed<=0;header_bad<=0;crc_bad<=0;verify_bad<=0;
     state<=state==READ_ISSUE?READ_WAIT:VERIFY_WAIT;
    end
    READ_WAIT,VERIFY_WAIT:if(read_done)begin io_failed<=io_failed || read_error!=0;state<=state==READ_WAIT?CHECK:VERIFY_CHECK;end
    CHECK:begin
     if(io_failed)boot_read_failed<=1;
     if(record_ok && newer)begin
      restore_valid<=1;restore_track<=rx_track;
      generation<=rx_generation;have_latest<=1;latest_slot<=slot;
      copy_index<=12;state<=COPY_ISSUE;
     end else state<=FINISH_CHECK;
    end
    COPY_ISSUE:state<=COPY_APPLY;
    COPY_APPLY:begin
     if(copy_index>=12)restore_frame<={candidate_q,restore_frame[31:8]};
     else if(copy_index<4)restore_size<={candidate_q,restore_size[31:8]};
     else restore_cluster<={candidate_q,restore_cluster[31:8]};
     copy_index<=copy_index+1'b1;
     state<=copy_index==7?FINISH_CHECK:COPY_ISSUE;
    end
    FINISH_CHECK:begin
     if(!slot)begin slot<=1;state<=LOAD_B;end
     else begin boot_ready<=1;enabled<=!boot_read_failed && !io_failed;save_error<=boot_read_failed || io_failed;state<=IDLE;end
    end
    IDLE:if(enabled && snapshot_valid && changed)begin
      restore_track<=snapshot_track;restore_frame<=snapshot_frame;restore_size<=snapshot_size;restore_cluster<=snapshot_cluster;
      address_work<={2'b0,snapshot_size[31:2]};state<=SNAP_LIMIT;
    end
    SNAP_LIMIT:begin address_work<=address_sum;state<=SNAP_COMPARE;end
    SNAP_COMPARE:begin
      frame_hi_lt<=restore_frame[31:16]<address_work[31:16];
      frame_hi_eq<=restore_frame[31:16]==address_work[31:16];
      frame_lo_lt<=restore_frame[15:0]<address_work[15:0];state<=SNAP_CHECK;
    end
    SNAP_CHECK:begin
      if(restore_size>44 && (frame_hi_lt || (frame_hi_eq && frame_lo_lt)))begin
       crc<=32'hffffffff;crc_bits<=0;build_index<=0;slot<=have_latest?!latest_slot:1'b0;state<=BUILD;address_write<=1;
      end else begin force_save<=1;state<=IDLE;end
    end
    BUILD:if(crc_bits==0)begin
     if(build_index<24)begin crc<=crc^{24'd0,record_byte};crc_bits<=8;build_index<=build_index+1'b1;end
     else if(bus_granted)begin tx_index<=0;state<=LOAD_B;end
    end
    WRITE_WAIT:begin
     if(write_next)begin write_byte<=tx_index<32?record_byte:8'd0;tx_index<=tx_index+1'b1;end
     if(write_done)begin
      if(write_error || tx_index!=512)begin save_error<=1;enabled<=0;state<=IDLE;end else state<=VERIFY_ISSUE;
     end
    end
    VERIFY_CHECK:begin
     if(record_ok && !verify_bad)begin generation<=next_generation;have_latest<=1;latest_slot<=slot;force_save<=0;end
     else begin save_error<=1;enabled<=0;end
     state<=IDLE;
    end
    default:state<=WAIT_CATALOG;
   endcase
  end
 end
endmodule
