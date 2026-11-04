`timescale 1ns/1ps
module library_neighbor_finder(
 input wire clk,rst_n,request,previous,
 input wire [3:0] current,
 input wire [15:0] playable,
 output reg busy,done,found,
 output reg [3:0] target
);
 reg backwards;
 reg [3:0] candidate;
 reg [4:0] remaining;
 reg [15:0] available;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;done<=0;found<=0;target<=0;backwards<=0;candidate<=0;remaining<=0;available<=0;end
  else begin
   done<=0;
   if(request&&!busy)begin
    busy<=1;found<=0;backwards<=previous;available<=playable;remaining<=16;
    candidate<=previous?current-1'b1:current+1'b1;
   end else if(busy)begin
    if(available[candidate])begin target<=candidate;found<=1;done<=1;busy<=0;end
    else if(remaining==1)begin found<=0;done<=1;busy<=0;end
    else begin candidate<=backwards?candidate-1'b1:candidate+1'b1;remaining<=remaining-1'b1;end
   end
  end
 end
endmodule
