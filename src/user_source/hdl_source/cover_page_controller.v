`timescale 1ns/1ps
module cover_page_controller(
 input wire clk,rst_n,init_ready,reload_request,
 input wire [1:0] requested_page,
 input wire sector_busy,cache_done,metadata_done,
 input wire [1:0] metadata_page,
 output wire reloading,quiescing,cache_invalidate,
 output reg catalog_start,
 output reg [1:0] catalog_page,active_page,
 output reg page_done
);
 localparam IDLE=0,DRAIN=1,RESET=2,METADATA=3,LOAD=4;
 reg [2:0] state;
 reg [1:0] settle;
 reg seen_loading;
 assign reloading=state!=IDLE||reload_request;
 assign quiescing=state==DRAIN||state==RESET||state==METADATA||reload_request;
 assign cache_invalidate=state==RESET;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;settle<=0;seen_loading<=0;
   catalog_start<=0;catalog_page<=0;active_page<=0;page_done<=0;
  end else begin
   catalog_start<=0;page_done<=0;
   if(metadata_done)active_page<=metadata_page;
   if(!init_ready)begin state<=IDLE;settle<=0;seen_loading<=0;end
   else case(state)
    IDLE:if(reload_request&&cache_done)begin
     catalog_page<=requested_page;settle<=0;state<=DRAIN;
    end
    DRAIN:if(sector_busy)settle<=0;
          else if(settle==2)begin settle<=0;state<=RESET;end
          else settle<=settle+1'b1;
    RESET:if(settle==1)begin catalog_start<=1;state<=METADATA;end
          else settle<=settle+1'b1;
    METADATA:if(metadata_done)begin state<=LOAD;seen_loading<=0;end
    LOAD:begin
     if(!cache_done)seen_loading<=1;
     if(cache_done&&seen_loading)begin state<=IDLE;page_done<=1;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
