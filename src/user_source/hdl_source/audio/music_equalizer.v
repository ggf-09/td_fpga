`timescale 1ns/1ps
// Complementary three-band EQ, 48 kHz. Q8 sample states, Q16 one-pole
// crossover coefficients (200 Hz, 4 kHz). One shared signed multiplier.
// Low + mid + high == input exactly at neutral gain. No frame RAM needed.
// Q8 gains slew one unit per accepted audio frame to soften adjustments.
module music_equalizer #(parameter integer CLIP_HOLD_SAMPLES=48000)(
 input wire clk,rst_n,clear,
 input wire in_valid, output wire in_ready,
 input wire signed [15:0] in_left,in_right,
 input wire [2:0] bass,mid,treble,
 input wire [4:0] volume,
 output reg out_valid,input wire out_ready,
 output reg signed [15:0] out_left,out_right,
 output reg clipped
);
 reg [3:0] state;
 reg channel;
 reg signed [23:0] lp_low[0:1],lp_high[0:1];
 reg signed [23:0] x,left_x,right_x,lo,hi;
 reg signed [39:0] accumulator;
 reg signed [31:0] operand_a;
 reg signed [15:0] operand_b;
 wire signed [47:0] product=operand_a*operand_b;
 // Gain states stay between current and target: all targets are 0..512.
 // Ten unsigned bits retain every original value and slew step.
 reg [9:0] bass_gain,mid_gain,treble_gain,volume_gain;
 reg [9:0] bass_q,mid_q,treble_q,volume_q;
 reg [15:0] clip_hold;
 function [9:0] gain;
 input [2:0] level;
 begin case(level)
  0:gain=128; 1:gain=181; 2:gain=256; 3:gain=362; default:gain=512;
 endcase end endfunction
 function [9:0] slew;
 input [9:0] value,target;
 begin
  if(value<target)slew=value+1'b1;
  else if(value>target)slew=value-1'b1;
  else slew=value;
 end endfunction
 function signed [15:0] saturate;
 input signed [47:0] value;
 begin if(value>32767) saturate=32767;
 else if(value< -32768) saturate=-32768;
 else saturate=value[15:0]; end endfunction
 assign in_ready=!clear && state==0 && (!out_valid || out_ready);
 always @* begin
  operand_a=0;operand_b=0;
  case(state)
   1:begin operand_a=$signed(x)-$signed(lp_low[channel]);operand_b=1693;end
   2:begin operand_a=$signed(x)-$signed(lp_high[channel]);operand_b=26713;end
   3:begin operand_a=lo;operand_b=bass_q;end
   4:begin operand_a=$signed(hi)-$signed(lo);operand_b=mid_q;end
   5:begin operand_a=$signed(x)-$signed(hi);operand_b=treble_q;end
   6:begin operand_a=accumulator>>>8;operand_b=volume_q;end
   default:begin end
  endcase
 end
 wire signed [47:0] scaled=product>>>16;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=0;channel<=0;out_valid<=0;out_left<=0;out_right<=0;clipped<=0;
   clip_hold<=0;
   lp_low[0]<=0;lp_low[1]<=0;lp_high[0]<=0;lp_high[1]<=0;
   x<=0;left_x<=0;right_x<=0;lo<=0;hi<=0;accumulator<=0;
   bass_q<=256;mid_q<=256;treble_q<=256;volume_q<=256;
   bass_gain<=256;mid_gain<=256;treble_gain<=256;volume_gain<=256;
  end else if(clear) begin
   state<=0;out_valid<=0;clipped<=0;
   clip_hold<=0;
   lp_low[0]<=0;lp_low[1]<=0;lp_high[0]<=0;lp_high[1]<=0;
   bass_gain<=256;mid_gain<=256;treble_gain<=256;volume_gain<=256;
  end else begin
   if(out_valid && out_ready) out_valid<=0;
   case(state)
    0:if(in_valid && in_ready) begin
     // Count accepted stereo frames, not processing clocks. Either
     // channel may refresh the one-second peak indicator below.
     if(clip_hold!=0) begin
      clip_hold<=clip_hold-1'b1;
      if(clip_hold==1)clipped<=0;
     end
     left_x<={in_left,8'd0};right_x<={in_right,8'd0};x<={in_left,8'd0};
     bass_q<=slew(bass_gain,gain(bass));bass_gain<=slew(bass_gain,gain(bass));
     mid_q<=slew(mid_gain,gain(mid));mid_gain<=slew(mid_gain,gain(mid));
     treble_q<=slew(treble_gain,gain(treble));treble_gain<=slew(treble_gain,gain(treble));
     volume_q<=slew(volume_gain,{1'b0,volume,4'd0});volume_gain<=slew(volume_gain,{1'b0,volume,4'd0});
     channel<=0;state<=1;
    end
    1:begin lo<=lp_low[channel]+(product>>>16);state<=2;end
    2:begin hi<=lp_high[channel]+(product>>>16);state<=3;end
    3:begin accumulator<=product;state<=4;end
    4:begin accumulator<=accumulator+product;state<=5;end
    5:begin accumulator<=accumulator+product;state<=6;end
    6:begin
     lp_low[channel]<=lo;lp_high[channel]<=hi;
     if(scaled>32767 || scaled< -32768) begin
      clipped<=1;
      clip_hold<=CLIP_HOLD_SAMPLES;
     end
     if(!channel) begin out_left<=saturate(scaled);channel<=1;x<=right_x;state<=1;end
     else begin out_right<=saturate(scaled);out_valid<=1;state<=0;end
    end
    default:state<=0;
   endcase
  end
 end
endmodule
