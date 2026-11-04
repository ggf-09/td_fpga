`timescale 1ns/1ps
// Startup recovery uses the existing page/cover route, including songs 5..16.
module resume_startup(
 input wire clk,rst_n,boot_ready,record_valid,
 input wire [3:0] record_track,input wire [15:0] playable,
 input wire route_ready,manual_accepted,input wire [3:0] current_track,
 input wire consumed,user_cancel,
 output wire hold_audio,output reg route_request,output wire [3:0] route_target,
 output wire apply_position,output wire ready
);
 localparam INFO=0,ROUTER=1,ACCEPT=2,ROUTE=3,DONE=4;
 reg [2:0] state;reg armed;
 assign hold_audio=state!=DONE;
 assign ready=state==DONE;
 assign route_target=record_track;
 assign apply_position=armed && current_track==record_track;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=INFO;armed<=0;route_request<=0;end
  else begin
   route_request<=0;
   if(consumed || user_cancel)armed<=0;
   case(state)
    INFO:if(boot_ready)begin
     if(record_valid && playable[record_track])state<=ROUTER;else state<=DONE;
    end
    ROUTER:if(route_ready)begin route_request<=1;state<=ACCEPT;end
    // Initial video commit can raise fade_busy one clock after route_ready.
    // Hold this request until the router acknowledges it; a one-clock pulse
    // can otherwise be lost while the opening transition is starting.
    ACCEPT:if(manual_accepted)state<=ROUTE;else route_request<=1;
    ROUTE:if(route_ready)begin armed<=current_track==record_track;state<=DONE;end
    DONE:;
    default:state<=INFO;
   endcase
  end
 end
endmodule

// Validate a frozen startup record over several clocks. The selected FAT
// descriptor is captured first so its mux, subtraction and range comparison
// do not form a single 100 MHz path into the WAV transport.
module resume_file_validator(
 input wire clk,rst_n,check_req,
 input wire [31:0] actual_size,actual_cluster,saved_size,saved_cluster,saved_frame,
 output reg ready,valid,output reg [31:0] start_offset
);
 reg [2:0] state;
 reg [29:0] frame_limit;
 reg size_ok,identity_ok,identity_low,identity_high,hi_lt,hi_eq,lo_lt;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;ready<=0;valid<=0;end
  else if(!check_req)begin state<=0;ready<=0;valid<=0;end
  else case(state)
   0:begin
    // The saved record is held by playback_checkpoint until startup consumes
    // it. Reuse frame_limit for the two arithmetic stages instead of copying
    // the full descriptors and saved frame into another set of registers.
    frame_limit<=actual_size[31:2];size_ok<=actual_size>44;
    identity_low<=actual_size[15:0]==saved_size[15:0] && actual_cluster[15:0]==saved_cluster[15:0];
    identity_high<=actual_size[31:16]==saved_size[31:16] && actual_cluster[31:16]==saved_cluster[31:16];
    state<=1;
   end
   1:begin
    frame_limit<=frame_limit-30'd11;
    identity_ok<=identity_low && identity_high;
    start_offset<=44+{saved_frame[29:0],2'b00};state<=2;
   end
   2:begin
    hi_lt<=saved_frame[31:16]<{2'd0,frame_limit[29:16]};
    hi_eq<=saved_frame[31:16]=={2'd0,frame_limit[29:16]};
    lo_lt<=saved_frame[15:0]<frame_limit[15:0];state<=3;
   end
   3:begin valid<=size_ok && identity_ok && (hi_lt || (hi_eq && lo_lt));ready<=1;state<=4;end
   default:;
  endcase
 end
endmodule

// Request/acknowledge bundle transfer. Source holds every bit until the next
// synchronized request; destination captures only after the acknowledge.
module checkpoint_snapshot_cdc #(parameter integer WIDTH=38)(
 input wire src_clk,src_rst_n,dst_clk,dst_rst_n,
 input wire [WIDTH-1:0] source_bundle,
 output reg [WIDTH-1:0] destination_bundle
);
 reg request,req_s1,req_s2,ack,ack_d1,ack_d2;
 reg [WIDTH-1:0] held;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin req_s1<=0;req_s2<=0;ack<=0;held<=0;end
  else begin
   req_s1<=request;req_s2<=req_s1;
   if(req_s2!=ack)begin held<=source_bundle;ack<=req_s2;end
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin request<=1;ack_d1<=0;ack_d2<=0;destination_bundle<=0;end
  else begin
   ack_d1<=ack;ack_d2<=ack_d1;
   if(ack_d2==request)begin destination_bundle<=held;request<=!request;end
  end
 end
endmodule
