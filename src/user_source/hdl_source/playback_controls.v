`timescale 1ns/1ps
// All gestures are emitted on debounced release. Single-click waits for
// the double-click window; long presses never leak a short-click action.
module playback_gesture #(parameter integer CLOCK_HZ=100000000,
                         parameter integer DOUBLE_CLICK=0,
                         parameter integer ON_PRESS=0,REPEAT=0)(
 input wire clk,rst_n,key_n,
 output reg single_click,double_click,long_click,very_long_click,repeat_click
);
 // 人因调整（2026-10-27实机反馈"歌单KEY4调亮度/对比度时间窗口太短控制不了"）：
 // VERY_LONG 3s→6s——歌单内亮度=长按1.2~6s松开，对比度=≥6s超长按。
 // DOUBLE_TIME 0.5s→0.8s——双击（切播放模式/进出歌单）判定窗放宽。
 // 100MHz下DOUBLE_TIME=80M、VERY_LONG=600M，分别至少需要27/30位计数器；
 // 位宽不足会在硬件截断/绕回，而低速仿真无法暴露。
 localparam integer DB=CLOCK_HZ/50, LONG=CLOCK_HZ*12/10;
 localparam integer VERY_LONG=CLOCK_HZ*6, DOUBLE_TIME=CLOCK_HZ*4/5;
 reg sync1,sync2,stable;
 localparam integer DB_BITS=DB>1?$clog2(DB+1):1;
 localparam integer HELD_BITS=VERY_LONG>1?$clog2(VERY_LONG+1):1;
 localparam integer PENDING_BITS=DOUBLE_TIME>1?$clog2(DOUBLE_TIME+1):1;
 reg [DB_BITS-1:0] debounce;
 reg debounce_last;
 reg [HELD_BITS-1:0] held;
 reg [PENDING_BITS-1:0] pending;
 // 按住连发（仅REPEAT=1的拨码调节键启用）：按下0.5s后每~0.15s再发一档，
 // 解决实机"音量要按十几次才到顶、按住不动只加一档"的痛点。
 localparam integer REPEAT_DELAY=CLOCK_HZ/2, REPEAT_PERIOD=CLOCK_HZ/7;
 localparam integer REP_BITS=(REPEAT_DELAY+REPEAT_PERIOD)>1?$clog2(REPEAT_DELAY+REPEAT_PERIOD+1):1;
 reg [REP_BITS-1:0] rep_cnt;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin rep_cnt<=0;repeat_click<=0;end
  else begin
   repeat_click<=0;
   if(REPEAT==0 || ON_PRESS==0 || stable) rep_cnt<=0;
   else if(rep_cnt<REPEAT_DELAY) rep_cnt<=rep_cnt+1'b1;
   else if(rep_cnt>=REPEAT_DELAY+REPEAT_PERIOD-1) begin rep_cnt<=REPEAT_DELAY;repeat_click<=1;end
   else rep_cnt<=rep_cnt+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   sync1<=1;sync2<=1;stable<=1;debounce<=0;debounce_last<=0;held<=0;pending<=0;
   single_click<=0;double_click<=0;long_click<=0;very_long_click<=0;
  end else begin
   sync1<=key_n;sync2<=sync1;
   single_click<=0;double_click<=0;long_click<=0;very_long_click<=0;
   if(pending!=0) begin
    pending<=pending-1'b1;
    if(pending==1) single_click<=1;
   end
   if(!stable && held<VERY_LONG) held<=held+1'b1;
   if(sync2==stable) begin debounce<=0;debounce_last<=0;end
   else if(DB<=1 || debounce_last) begin
    stable<=sync2;debounce<=0;debounce_last<=0;
    if(!sync2) begin held<=0;if(ON_PRESS!=0) single_click<=1;end
    else begin
     held<=0;
     if(ON_PRESS!=0) begin end
     else if(held>=LONG) begin
      pending<=0; single_click<=0;
      if(held>=VERY_LONG) very_long_click<=1;else long_click<=1;
     end else if(DOUBLE_CLICK!=0) begin
      if(pending!=0) begin pending<=0;single_click<=0;double_click<=1;end
      else pending<=DOUBLE_TIME;
     end else single_click<=1;
    end
   end else begin debounce<=debounce+1'b1;debounce_last<=debounce==DB-2;end
  end
 end
endmodule

module playback_controls #(parameter integer CLOCK_HZ=100000000)(
 input wire clk,rst_n,key_next_n,key_pause_n,key_view_n,thumbnail,volume_switch,
 input wire [2:0] eq_switches,
 output wire next_song,previous_song,thumb_right,thumb_left,thumb_confirm,thumb_toggle,
 output wire mode_next,
 output reg paused,
 output reg [4:0] volume,
 output reg [2:0] brightness,contrast,
 output wire volume_mode,
 output reg [2:0] bass,mid,treble,
 output reg [3:0] edit_target,
 output wire seek_backward,seek_forward,seek_mode,
 output reg transition_pref,
 output wire clean_mode,
 output reg [1:0] lyric_alpha,
 output reg [2:0] lyric_position
);
 localparam integer DB=CLOCK_HZ/50;
 reg [3:0] switch_s1,switch_s2,switch_setting;
 reg keys_up1,keys_up2,keys_armed;
 localparam integer DB_BITS=DB>1?$clog2(DB+1):1;
 reg [DB_BITS-1:0] switch_count,release_count;
 wire switch_change=(switch_s2!=switch_setting)&&(switch_count==DB-1);
 assign seek_mode=switch_setting==4'b0011;
 assign clean_mode=switch_setting==4'b1010;
 assign volume_mode=edit_target==1;
 always @* begin
  if(seek_mode) edit_target=5;
  else if(switch_setting==4'b0101) edit_target=6;
  else if(switch_setting==4'b1001) edit_target=7;
  else if(switch_setting==4'b0110) edit_target=8;
  else if(switch_setting==4'b1100) edit_target=9;
  else if(switch_setting==4'b1110) edit_target=10;
  else if(clean_mode) edit_target=0;
  else if(switch_setting[0]) edit_target=1;
  else if(switch_setting[1]) edit_target=2;
  else if(switch_setting[2]) edit_target=3;
  else if(switch_setting[3]) edit_target=4;
  else edit_target=0;
 end
 // Debounce the toggle, and require both remapped keys to be released
 // before arming. A held key or pending double-click cannot cross modes.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   switch_s1<=0;switch_s2<=0;switch_setting<=0;switch_count<=0;
   keys_up1<=0;keys_up2<=0;keys_armed<=0;release_count<=0;
  end else begin
   switch_s1<={eq_switches,volume_switch};switch_s2<=switch_s1;
   keys_up1<=key_pause_n&&key_view_n;keys_up2<=keys_up1;
   if(switch_s2==switch_setting) switch_count<=0;
   else if(switch_change) begin switch_setting<=switch_s2;switch_count<=0;end
   else switch_count<=switch_count+1'b1;
   if(switch_change || switch_s2!=switch_setting) begin keys_armed<=0;release_count<=0;end
   else if(!keys_armed) begin
    if(!keys_up2) release_count<=0;
    else if(release_count==DB-1) begin keys_armed<=1;release_count<=0;end
    else release_count<=release_count+1'b1;
   end
  end
 end
 wire normal_keys=rst_n&&keys_armed&&(edit_target==0)&&!switch_change&&(switch_s2==switch_setting);
 wire volume_keys=rst_n&&keys_armed&&(edit_target!=0)&&!switch_change&&(switch_s2==switch_setting);
 wire ns,nd,nl,nv,ps,pd,pl,pv,vs,vd,vl,vv;
 playback_gesture #(.CLOCK_HZ(CLOCK_HZ)) n(clk,rst_n,key_next_n,ns,nd,nl,nv, );
 playback_gesture #(.CLOCK_HZ(CLOCK_HZ),.DOUBLE_CLICK(1)) p(clk,normal_keys,key_pause_n,ps,pd,pl,pv, );
 playback_gesture #(.CLOCK_HZ(CLOCK_HZ),.DOUBLE_CLICK(1)) v(clk,normal_keys,key_view_n,vs,vd,vl,vv, );
 wire volume_down,volume_up,vd_once,vd_rep,vu_once,vu_rep;
 playback_gesture #(.CLOCK_HZ(CLOCK_HZ),.ON_PRESS(1),.REPEAT(1)) vp(clk,volume_keys,key_pause_n,vd_once, , , ,vd_rep);
 playback_gesture #(.CLOCK_HZ(CLOCK_HZ),.ON_PRESS(1),.REPEAT(1)) vvkey(clk,volume_keys,key_view_n,vu_once, , , ,vu_rep);
 assign volume_down=vd_once|vd_rep;
 assign volume_up=vu_once|vu_rep;
 assign seek_backward=volume_down && seek_mode && volume_keys && !volume_up;
 assign seek_forward=volume_up && seek_mode && volume_keys && !volume_down;
 assign next_song=ns&&!thumbnail;
 assign previous_song=(nl||nv)&&!thumbnail;
 assign thumb_right=ns&&thumbnail;
 assign thumb_confirm=(nl||nv)&&thumbnail;
 assign thumb_left=vs&&thumbnail&&normal_keys;
 assign thumb_toggle=vd&&normal_keys;
 assign mode_next=pd&&normal_keys;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin paused<=0;volume<=16;brightness<=0;contrast<=0;bass<=2;mid<=2;treble<=2;transition_pref<=0;lyric_alpha<=1;lyric_position<=7;end
  else begin
   if(ps&&normal_keys) paused<=!paused;
   if(next_song||previous_song||thumb_confirm) paused<=0;
   if(normal_keys) begin
    if(vl&&thumbnail) brightness<=brightness==4?0:brightness+1'b1;
    if(vv&&thumbnail) contrast<=contrast==4?0:contrast+1'b1;
   end else if(volume_keys) begin
    if(volume_down ^ volume_up) case(edit_target)
     1:if(volume_up&&volume<16)volume<=volume+1'b1;
       else if(volume_down&&volume>0)volume<=volume-1'b1;
     2:if(volume_up&&bass<4)bass<=bass+1'b1;
       else if(volume_down&&bass>0)bass<=bass-1'b1;
     3:if(volume_up&&mid<4)mid<=mid+1'b1;
       else if(volume_down&&mid>0)mid<=mid-1'b1;
     4:if(volume_up&&treble<4)treble<=treble+1'b1;
       else if(volume_down&&treble>0)treble<=treble-1'b1;
     6:if(volume_up&&brightness<4)brightness<=brightness+1'b1;
       else if(volume_down&&brightness>0)brightness<=brightness-1'b1;
     7:if(volume_up&&contrast<4)contrast<=contrast+1'b1;
       else if(volume_down&&contrast>0)contrast<=contrast-1'b1;
     8:if(volume_up)transition_pref<=1'b1;
       else transition_pref<=1'b0;
     9:if(volume_up&&lyric_alpha<3)lyric_alpha<=lyric_alpha+1'b1;
       else if(volume_down&&lyric_alpha>0)lyric_alpha<=lyric_alpha-1'b1;
     10:if(volume_up&&lyric_position<7)lyric_position<=lyric_position+1'b1;
        else if(volume_down&&lyric_position>0)lyric_position<=lyric_position-1'b1;
     default:;
    endcase
   end
  end
 end
endmodule

// Linear 0..16 user gain. Registered so this does not extend the HDMI path.
module playback_volume(
 input wire clk,rst_n,valid_in,paused,
 input wire [4:0] volume,
 input wire signed [15:0] left_in,right_in,
 output reg valid_out,
 output reg signed [15:0] left_out,right_out
);
 wire signed [21:0] l=left_in*$signed({1'b0,volume});
 wire signed [21:0] r=right_in*$signed({1'b0,volume});
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin valid_out<=0;left_out<=0;right_out<=0;end
  else begin
   valid_out<=valid_in;
   if(valid_in) begin
    left_out<=paused?16'sd0:(l>>>4);
    right_out<=paused?16'sd0:(r>>>4);
   end
  end
 end
endmodule
