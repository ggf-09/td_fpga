`timescale 1ns/1ps
module playback_sequence #(parameter integer INDEX_WIDTH=2,TRACKS=(1<<INDEX_WIDTH))(
 input wire clk,rst_n,mode_next,eof,manual_start,paused,route_ready,
 input wire [TRACKS-1:0] playable,
 input wire [INDEX_WIDTH-1:0] current,
 output wire [1:0] mode,
 output wire advance,
 output wire [INDEX_WIDTH-1:0] target,
 output wire replay,stopped
);
generate if(INDEX_WIDTH==2 && TRACKS==4)begin:g_legacy
 playback_sequence_legacy core(clk,rst_n,mode_next,eof,manual_start,paused,route_ready,playable,current,mode,advance,target,replay,stopped);
end else begin:g_library
 playback_sequence_serial #(.INDEX_WIDTH(INDEX_WIDTH),.TRACKS(TRACKS)) core(clk,rst_n,mode_next,eof,manual_start,paused,route_ready,playable,current,mode,advance,target,replay,stopped);
end endgenerate
endmodule
`timescale 1ns/1ps
// Advance only on drained audio EOF, never on a wall-clock picture timer.
// mode 0: playlist loop; 1: ordered, stop at end; 2: pseudo-random.
module playback_sequence_legacy(
 input wire clk,rst_n,mode_next,eof,manual_start,paused,route_ready,
 input wire [3:0] playable,
 input wire [1:0] current,
 output reg [1:0] mode,
 output reg advance,
 output reg [1:0] target,
 output reg replay,stopped
);
 reg pending;
 reg [15:0] random_state;
 reg [1:0] candidate;
 reg found;
 reg [2:0] count,rank;
 reg [3:0] choices;
 integer i;
 always @* begin
  candidate=current;found=0;count=0;rank=0;choices=playable;
  if(mode==2) begin
   // With multiple tracks, exclude the current track to avoid repeats.
   if((playable & (playable-1'b1))!=0) choices[current]=0;
   for(i=0;i<4;i=i+1) if(choices[i]) count=count+1'b1;
   case(count)
    1:rank=0;
    2:rank={2'b0,random_state[0]};
    3:rank=(random_state[1:0]==3)?0:{1'b0,random_state[1:0]};
    default:rank={1'b0,random_state[1:0]};
   endcase
   for(i=0;i<4;i=i+1) if(choices[i]&&!found) begin
    if(rank==0) begin candidate=i[1:0];found=1;end
    else rank=rank-1'b1;
   end
  end else begin
   // Ordered successor, then wrap only in loop mode.
   for(i=0;i<4;i=i+1)
    if(i>current&&playable[i]&&!found) begin candidate=i[1:0];found=1;end
   if(!found&&mode==0)
    for(i=0;i<4;i=i+1)
     if(playable[i]&&!found) begin candidate=i[1:0];found=1;end
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   mode<=0;advance<=0;target<=0;replay<=0;stopped<=0;pending<=0;
   random_state<=16'h1ace;
  end else begin
   random_state<={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
   advance<=0;replay<=0;
   if(mode_next) begin
    mode<=mode==2?0:mode+1'b1;
    if(stopped) begin pending<=1;stopped<=0;end
   end
   if(eof) pending<=1;
   if(pending&&!paused&&route_ready&&!mode_next) begin
    pending<=0;
    if(found) begin
     target<=candidate;
     if(candidate==current) replay<=1;else advance<=1;
     stopped<=0;
    end else stopped<=1;
   end
   // A user's accepted selection always supersedes an EOF still waiting.
   if(manual_start) begin pending<=0;stopped<=0;advance<=0;replay<=0;end
  end
 end
endmodule

module playback_sequence_serial #(parameter integer INDEX_WIDTH=4,TRACKS=(1<<INDEX_WIDTH))(
 input wire clk,rst_n,mode_next,eof,manual_start,paused,route_ready,
 input wire [TRACKS-1:0] playable,
 input wire [INDEX_WIDTH-1:0] current,
 output reg [1:0] mode,
 output reg advance,
 output reg [INDEX_WIDTH-1:0] target,
 output reg replay,stopped
);
 localparam IDLE=0,SEARCH=1,COMMIT=2;
 reg [1:0] state;
 reg pending,found;
 reg [15:0] random_state;
 reg [TRACKS-1:0] available;
 reg [INDEX_WIDTH-1:0] cursor,origin,chosen;
 reg [INDEX_WIDTH:0] remaining;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;pending<=0;found<=0;random_state<=16'h1ace;available<=0;
   cursor<=0;origin<=0;chosen<=0;remaining<=0;
   mode<=0;advance<=0;target<=0;replay<=0;stopped<=0;
  end else begin
   random_state<={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
   advance<=0;replay<=0;
   if(eof)pending<=1;
   case(state)
    IDLE:if(pending&&!paused&&route_ready&&!mode_next)begin
     available<=playable;origin<=current;found<=0;remaining<=TRACKS;
     cursor<=mode==2?random_state[INDEX_WIDTH-1:0]:(current==TRACKS-1?0:current+1'b1);
     state<=SEARCH;
    end
    SEARCH:begin
     if(mode==1 && cursor<=origin)state<=COMMIT;
     else if(available[cursor] && (mode!=2 || cursor!=origin))begin
      chosen<=cursor;found<=1;state<=COMMIT;
     end else if(remaining==1 || (mode==1 && cursor==TRACKS-1))begin
      if(mode==2&&available[origin])begin chosen<=origin;found<=1;end
      state<=COMMIT;
     end else begin
      cursor<=cursor==TRACKS-1?0:cursor+1'b1;remaining<=remaining-1'b1;
     end
    end
    COMMIT:if(!paused&&route_ready&&!mode_next)begin
     pending<=0;state<=IDLE;stopped<=!found;
     if(found)begin
      target<=chosen;
      if(chosen==origin)replay<=1;else advance<=1;
     end
    end
    default:state<=IDLE;
   endcase
   if(mode_next)begin
    mode<=mode==2?0:mode+1'b1;state<=IDLE;
    if(stopped)begin pending<=1;stopped<=0;end
   end
   if(manual_start)begin pending<=0;state<=IDLE;stopped<=0;advance<=0;replay<=0;end
  end
 end
endmodule
