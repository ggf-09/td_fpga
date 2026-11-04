`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// 第15课：thumbnail_controller（缩略图交互控制器）
// 来源：第14课（缩略图交互选择）练习骨架 + 3.2.2参考答案补全四个TODO。
// 顶层接线适配（与课件完赛工程不同，勿改回课件接法）：
//   本工程板子只有key1/key2有引脚约束，没有独立方向/确认/模式键——
//   key_right  = KEY1在缩略图模式下短按松开（顶层sd域导航块产生单拍脉冲）
//   key_left   = KEY2在缩略图模式下单击
//   key_confirm= KEY1在缩略图模式下按住≥1.2s松开
//   key_mode   = KEY2双击（≤0.5s，双模式通用）
//   均为sd_card_clk域单拍脉冲，本模块工作在sd_card_clk域。
//   view_mode输出是"期望模式"：顶层在转场全黑时刻才应用到thumb_mode_sd
//   （淡出盖住坐标映射切换，无pop）；active_index输出不接——快速选择由顶层
//   在key_confirm时锁存focus_index、全黑时刻pulse u_control.select_event
//   （复用第8课"双缓冲原子提交"通道，即课件钩子2）。
// -----------------------------------------------------------------------------
module thumbnail_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_right,   // 消抖后单拍：焦点右移
    input  wire        key_left,    // 消抖后单拍：焦点左移
    input  wire        key_confirm, // 消抖后单拍：选中当前焦点
    input  wire        key_mode,    // 消抖后单拍：全屏/缩略图切换
    input  wire [3:0]  image_complete,
    input  wire        frame_start, // 帧边界（sd域同步后的单拍脉冲）
    output reg         view_mode,   // 0=全屏 1=缩略图
    output reg [1:0]   focus_index,
    output reg [1:0]   active_index,
    output reg         transition_req,
    output reg         transition_select
);
    reg trans_pend;
    reg select_pend;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            view_mode      <= 1'b0;   // 复位：全屏、焦点0、当前图0
            focus_index    <= 2'd0;
            active_index   <= 2'd0;
            transition_req <= 1'b0;
            trans_pend     <= 1'b0;
            select_pend<=0;transition_select<=0;
        end else begin
            transition_req <= 1'b0;   // 单拍脉冲，拍宽1拍后自动拉低（TODO4）
            transition_select<=0;
            if (key_mode) begin       // TODO1：模式切换
                view_mode  <= ~view_mode;
                trans_pend <= 1'b1;
                select_pend<=0;
            end
            // TODO2：方向键只在缩略图模式响应（全屏留给上一张/下一张）
            if (view_mode && key_right) begin
                focus_index <= (focus_index == 2'd3) ? 2'd0 : focus_index + 1'b1;
            end
            if (view_mode && key_left) begin
                focus_index <= (focus_index == 2'd0) ? 2'd3 : focus_index - 1'b1;
            end
            // TODO3：快速选择（未加载的图忽略，image_complete门控）
            if (key_confirm && image_complete[focus_index]) begin
                active_index <= focus_index;
                view_mode    <= 1'b0;
                trans_pend   <= 1'b1;
                select_pend<=1;
            end
            // TODO4：transition_req在帧边界统一发出
            if (frame_start && trans_pend) begin
                transition_req <= 1'b1;
                trans_pend     <= 1'b0;
                transition_select<=select_pend;
            end
        end
    end
endmodule


// Browsing changes only a cursor. The audio/page router sees a global
// selection solely after confirmation; arrows never start a page load.
module library_browser_controller(
 input wire clk,rst_n,key_right,key_left,key_confirm,key_mode,frame_start,
 input wire busy,ready,menu_ready,
 input wire [15:0] playable,
 input wire [3:0] current_track,
 input wire [1:0] cache_page,
 output reg view_mode,
 output reg [3:0] focus_track,
 output reg transition_req,transition_select
);
 reg trans_pend,select_pend,nav_busy,nav_previous;
 reg [3:0] candidate,steps;
 wire [15:0] available=menu_ready?playable:(playable&(16'h000f<<{cache_page,2'b00}));
 // 后台加载期（ready=0）打开/关闭歌单和移动焦点不再阻塞：这些操作只动光标和视图。
 // 确认键也只查available：同页由router立即切或等槽落地，跨页由router锁存、
 // 整页载完后自动补发——用户按了就有结果，不会被静默吞掉。
 wire quiet=!busy&&!trans_pend&&!transition_req&&!nav_busy;
 wire confirm_ok=available[focus_track];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   view_mode<=0;focus_track<=0;transition_req<=0;transition_select<=0;
   trans_pend<=0;select_pend<=0;nav_busy<=0;nav_previous<=0;candidate<=0;steps<=0;
  end else begin
   transition_req<=0;transition_select<=0;
   if(!view_mode&&!trans_pend&&!busy)focus_track<=current_track;
   if(quiet)begin
    if(key_mode)begin
     view_mode<=!view_mode;trans_pend<=1;select_pend<=0;
     if(!view_mode)focus_track<=current_track;
    end else if(view_mode&&key_confirm&&confirm_ok)begin
     view_mode<=0;trans_pend<=1;select_pend<=1;
    end else if(view_mode&&(key_right||key_left))begin
     nav_busy<=1;nav_previous<=key_left;
     candidate<=key_left?focus_track-1'b1:focus_track+1'b1;steps<=0;
    end else if(view_mode&&!available[focus_track]&&available!=0)begin
     nav_busy<=1;nav_previous<=0;candidate<=current_track;steps<=0;
    end
   end
   if(nav_busy)begin
    if(available[candidate])begin focus_track<=candidate;nav_busy<=0;end
    else if(steps==15)nav_busy<=0;
    else begin candidate<=nav_previous?candidate-1'b1:candidate+1'b1;steps<=steps+1'b1;end
   end
   if(frame_start&&trans_pend&&!busy)begin
    transition_req<=1;transition_select<=select_pend;trans_pend<=0;
   end
  end
 end
endmodule

module library_browser_overlay(
 input wire enable,de,menu_ready,menu_card,paused,stopped,
 input wire [9:0] pixel_x,pixel_y,
 input wire [1:0] page,
 input wire [3:0] focus_track,playing_track,
 input wire [23:0] rgb_in,clean_rgb,
 output reg [23:0] rgb_out
);
 wire [4:0] focus_number={1'b0,focus_track}+1'b1,playing_number={1'b0,playing_track}+1'b1;
 wire [3:0] focus_ones=focus_number>=10?focus_number-10:focus_number;
 wire [3:0] playing_ones=playing_number>=10?playing_number-10:playing_number;
 wire [1:0] tile={pixel_y>=120,pixel_x>=160};
 wire [7:0] local_x=pixel_x>=160?pixel_x-160:pixel_x;
 wire [6:0] local_y=pixel_y>=120?pixel_y-120:pixel_y;
 wire playing_tile=playing_track[3:2]==page&&tile==playing_track[1:0];
 wire play_mark=pixel_x<320&&pixel_y<240&&playing_tile&&local_x>=143&&local_x<155&&
      local_y>=5&&local_y<19&&(local_x-143 <= (local_y<12?local_y-5:18-local_y));
 reg [7:0] character;
 reg [4:0] text_row;
 reg [5:0] text_col;
 reg [2:0] glyph_x,glyph_y;
 reg text_region;
 always @*begin
  character=32;text_row=0;text_col=0;glyph_x=0;glyph_y=0;text_region=0;
  if(pixel_x>=352&&pixel_y>=16&&pixel_y<240)begin
   text_region=1;text_row=(pixel_y-16)>>4;text_col=(pixel_x-352)>>4;
   glyph_x=((pixel_x-352)>>1)&7;glyph_y=((pixel_y-16)>>1)&7;
   case(text_row)
    0:case(text_col)0:character="P";1:character="A";2:character="G";3:character="E";5:character="1"+page;6:character="/";7:character="4";endcase
    2:case(text_col)0:character="F";1:character="O";2:character="C";3:character="U";4:character="S";6:character=focus_number>=10?"1":"0";7:character="0"+focus_ones;endcase
    4:case(text_col)0:character="N";1:character="O";2:character="W";4:character=playing_number>=10?"1":"0";5:character="0"+playing_ones;endcase
    5:case(text_col)0:character=stopped?"S":paused?"P":"P";1:character=stopped?"T":paused?"A":"L";2:character=stopped?"O":paused?"U":"A";3:character=stopped?"P":paused?"S":"Y";4:character=stopped?32:paused?"E":"I";5:character=stopped?32:paused?"D":"N";6:character=stopped||paused?32:"G";endcase
    7:case(text_col)0:character="K";1:character="2";3:character="N";4:character="E";5:character="X";6:character="T";endcase
    8:case(text_col)0:character="K";1:character="4";3:character="P";4:character="R";5:character="E";6:character="V";endcase
    10:case(text_col)0:character="H";1:character="O";2:character="L";3:character="D";5:character="K";6:character="2";8:character="P";9:character="L";10:character="A";11:character="Y";endcase
    12:case(text_col)0:character="2";1:character="X";3:character="K";4:character="4";6:character="E";7:character="X";8:character="I";9:character="T";endcase
   endcase
  end else if(pixel_x>=16&&pixel_y>=256&&pixel_y<272)begin
   text_region=1;text_col=(pixel_x-16)>>4;glyph_x=((pixel_x-16)>>1)&7;glyph_y=((pixel_y-256)>>1)&7;
   if(menu_ready)case(text_col)
    0:character="M";1:character="E";2:character="N";3:character="U";5:character="P";6:character="R";7:character="E";
   endcase
   else if(menu_card)case(text_col)
    0:character="F";1:character="P";2:character="G";3:character="A";
    5:character="6";6:character="4";7:character="0";8:character="X";
    9:character="4";10:character="8";11:character="0";
    13:character="T";14:character="O";
    16:character="1";17:character="6";18:character="0";19:character="X";
    20:character="1";21:character="2";22:character="0";
   endcase
   else case(text_col)
    0:character="A";1:character="D";2:character="D";4:character="M";5:character="E";6:character="N";7:character="U";8:character=".";9:character="B";10:character="M";11:character="P";
   endcase
  end
 end
 function [34:0] font;input [7:0] c;begin case(c)
  8'd48:font=35'b01110100011001110101110011000101110;
  8'd49:font=35'b00100011000010000100001000010001110;
  8'd50:font=35'b01110100010000100010001000100011111;
  8'd51:font=35'b11110000010000101110000010000111110;
  8'd52:font=35'b00010001100101010010111110001000010;
  8'd53:font=35'b11111100001000011110000010000111110;
  8'd54:font=35'b01110100001000011110100011000101110;
  8'd55:font=35'b11111000010001000100010000100001000;
  8'd56:font=35'b01110100011000101110100011000101110;
  8'd57:font=35'b01110100011000101111000010000101110;
  8'd65:font=35'b01110100011000111111100011000110001;
  8'd66:font=35'b11110100011000111110100011000111110;
  8'd67:font=35'b01111100001000010000100001000001111;
  8'd68:font=35'b11110100011000110001100011000111110;
  8'd69:font=35'b11111100001000011110100001000011111;
  8'd70:font=35'b11111100001000011110100001000010000;
  8'd71:font=35'b01111100001000010111100011000101111;
  8'd72:font=35'b10001100011000111111100011000110001;
  8'd73:font=35'b01110001000010000100001000010001110;
  8'd75:font=35'b10001100101010011000101001001010001;
  8'd76:font=35'b10000100001000010000100001000011111;
  8'd77:font=35'b10001110111010110101100011000110001;
  8'd78:font=35'b10001110011010110011100011000110001;
  8'd79:font=35'b01110100011000110001100011000101110;
  8'd80:font=35'b11110100011000111110100001000010000;
  8'd82:font=35'b11110100011000111110101001001010001;
  8'd83:font=35'b01111100001000001110000010000111110;
  8'd84:font=35'b11111001000010000100001000010000100;
  8'd85:font=35'b10001100011000110001100011000101110;
  8'd86:font=35'b10001100011000110001100010101000100;
  8'd87:font=35'b10001100011000110101101011101110001;
  8'd88:font=35'b10001100010101000100010101000110001;
  8'd89:font=35'b10001100010101000100001000010000100;
  8'd47:font=35'b00001000100001000100010000100010000;
  8'd46:font=35'b00000000000000000000000000011000110;
  default:font=0;
 endcase end endfunction
 wire [34:0] bits=font(character);
 wire text_pixel=text_region&&glyph_x<5&&glyph_y<7&&bits[(6-glyph_y)*5+4-glyph_x];
 always @*begin
  rgb_out=rgb_in;
  if(enable&&de)begin
   if(pixel_y<288)begin
    rgb_out=pixel_x<320&&pixel_y<240?clean_rgb:24'h0c121e;
    if(play_mark)rgb_out=24'h20e090;
    if(text_pixel)rgb_out=menu_ready?24'hd8e6fa:24'hffcc60;
   end
  end
 end
endmodule
