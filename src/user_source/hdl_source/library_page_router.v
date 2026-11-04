`timescale 1ns/1ps
// Global track identity is independent of the four physical cover buffers.
// Only change the cache at fade black; resume audio after cover commit ACK.
// 选中封面优先：PAGE态在目标槽就绪（页元数据已切换且该槽image_complete置位）
// 时立即放行出图，不等整页cache_done；其余槽由加载器后台补齐，失败槽的
// bad_covers标记延迟到cache_done单拍时补记（mark_pending）。
// 后台加载期间（cache_ready=0）仍受理同页请求：目标槽已就绪则黑场后立即切，
// 未就绪则在PAGE态等该槽落地（不触发整页重载、不停当前音频），避免提前放行后
// 到整页载完之间的按键死窗；跨页请求不丢弃——锁存后在整页载完时自动补发
// （加载控制器在LOAD态忽略reload_request，抢占需动加载关键路径，不做）。
// 重叠加载：跨页受理当拍即发page_start（与淡出并行，封面~0.9s出图而非淡出后才开始加载）。
// 目标槽≠当前显示槽时输出keep_slot=当前显示槽——loader整页失效时保留该槽的
// image_complete，旧封面在淡出期间保持显示不被顶层显示门控提前拉黑；
// 目标槽==显示槽（1/4情形）不发keep，保持fade_black才发page_start的串行流程
// （该槽马上被重写，旧封面本来就必须让位）。
module library_page_router #(parameter integer BROWSE_PAGING=0)(
 input wire clk,rst_n,
 input wire [15:0] catalog_playable,
 input wire [1:0] cache_page,
 input wire [3:0] cache_complete,
 input wire cache_ready,cache_done,
 input wire manual_request,manual_found,
 input wire [3:0] manual_target,
 input wire auto_request,
 input wire [3:0] auto_target,
 input wire view_request,view_select,target_view,
 input wire [1:0] focus_slot,focus_page,
 input wire fade_busy,fade_black,control_busy,
 output wire route_busy,sequence_ready,
 output wire [15:0] playable,
 output reg [3:0] current_track,pending_track,
 output reg audio_allowed,thumbnail,
 output reg fade_request,cover_select,
 output wire [1:0] cover_slot,
 output reg page_start,
 output wire [1:0] target_page,
 output reg manual_accepted,manual_same,
 output reg load_failed,abort_toggle,
 output reg keep_valid,      // 重叠跨页：loader整页失效时保留keep_slot槽的完成位
 output reg [1:0] keep_slot  // =受理时的当前显示槽（current_track[1:0]）
);
 localparam BOOT=0,IDLE=1,BLACK=2,PAGE=3,ACK_START=4,ACK_END=5;
 reg [2:0] state;
 reg requested_view;
 wire [3:0] focused_track={BROWSE_PAGING!=0?focus_page:cache_page,focus_slot};
 reg [15:0] bad_covers;
 wire [3:0] page_valid=(catalog_playable>>(cache_page*4))&cache_complete;
 reg [1:0] first_slot;
 reg mark_pending;
 reg same_page_wait;  // PAGE态是在等同页目标槽（未发page_start），区别于整页重载
 // 后台期跨页请求锁存：整页载完（cache_done/cache_ready）后自动补发
 reg pend_valid; reg [3:0] pend_track; reg pend_view,pend_sel;
 // 重叠加载：受理时已预发page_start则BLACK不再重发
 reg page_issued;
 wire target_loaded=cache_page==pending_track[3:2];
 integer i,j;
 always @* begin
  first_slot=0;
  for(i=3;i>=0;i=i-1)if(page_valid[i])first_slot=i[1:0];
 end
 assign route_busy=state!=IDLE;
 assign sequence_ready=state==IDLE&&!fade_busy&&cache_ready;
 assign playable=catalog_playable&~bad_covers;
 assign cover_slot=pending_track[1:0];
 assign target_page=pending_track[3:2];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=BOOT;bad_covers<=0;current_track<=0;pending_track<=0;
   audio_allowed<=0;thumbnail<=0;requested_view<=0;
   fade_request<=0;cover_select<=0;page_start<=0;
   manual_accepted<=0;manual_same<=0;load_failed<=0;abort_toggle<=0;mark_pending<=0;
   same_page_wait<=0;pend_valid<=0;pend_track<=0;pend_view<=0;pend_sel<=0;
   page_issued<=0;keep_valid<=0;keep_slot<=0;
  end else begin
   fade_request<=0;cover_select<=0;page_start<=0;
   manual_accepted<=0;manual_same<=0;load_failed<=0;
   // 提前放行页的坏槽补记：整页载完（cache_done单拍）时把未完成槽移出可播清单
   if(cache_done&&mark_pending)begin
    mark_pending<=1'b0;
    for(j=0;j<4;j=j+1)
     if(!cache_complete[j])bad_covers[{cache_page,j[1:0]}]<=1;
   end
   case(state)
    BOOT:if(cache_ready)begin
     if(page_valid!=0)begin
      pending_track<={cache_page,first_slot};cover_select<=1;state<=ACK_START;
     end else begin state<=IDLE;load_failed<=1;end
    end
    IDLE:if(!fade_busy)begin
     // 后台加载期（cache_ready=0）只即时受理同页/纯视图请求；跨页请求锁存，
     // 整页载完后自动补发。任何即时受理/补发都清掉旧锁存（最新意图优先）。
     // 每个分支自带页检查，多源同拍时不会借别人的同页条件误放行跨页目标。
     // 跨页受理（必为cache_ready/cache_done，控制器必在IDLE）当拍重叠发出page_start；
     // 目标槽≠显示槽时同时发keep保留旧封面供平滑淡出，==显示槽时走串行（BLACK再发）。
     if(manual_request&&manual_found&&(cache_ready||manual_target[3:2]==cache_page))begin
      pending_track<=manual_target;requested_view<=thumbnail;
      manual_accepted<=1;manual_same<=manual_target==current_track;
      fade_request<=1;state<=BLACK;pend_valid<=0;
      if(manual_target[3:2]!=cache_page&&manual_target[1:0]!=current_track[1:0])begin
       page_start<=1;page_issued<=1;keep_valid<=1;keep_slot<=current_track[1:0];
      end
     end else if(view_request&&(cache_ready||!view_select||focused_track[3:2]==cache_page))begin
      pending_track<=view_select?focused_track:current_track;
      requested_view<=target_view;fade_request<=1;state<=BLACK;
      // 纯视图切换只是打开/关闭歌单，不取消排队的换歌；选中曲目才是最新意图
      if(view_select)begin manual_accepted<=1;manual_same<=focused_track==current_track;pend_valid<=0;
       if(focused_track[3:2]!=cache_page&&focus_slot!=current_track[1:0])begin
        page_start<=1;page_issued<=1;keep_valid<=1;keep_slot<=current_track[1:0];
       end
      end
     end else if(auto_request&&cache_ready)begin
      pending_track<=auto_target;requested_view<=thumbnail;
      fade_request<=1;state<=BLACK;pend_valid<=0;
      if(auto_target[3:2]!=cache_page&&auto_target[1:0]!=current_track[1:0])begin
       page_start<=1;page_issued<=1;keep_valid<=1;keep_slot<=current_track[1:0];
      end
     end else if(pend_valid&&(cache_done||cache_ready))begin
      // 补发后台期锁存的跨页请求（淡出后走正常BLACK判页，优先加载仍生效）
      pending_track<=pend_track;requested_view<=pend_view;
      fade_request<=1;state<=BLACK;pend_valid<=0;
      if(pend_sel)begin manual_accepted<=1;manual_same<=pend_track==current_track;end
      if(pend_track[3:2]!=cache_page&&pend_track[1:0]!=current_track[1:0])begin
       page_start<=1;page_issued<=1;keep_valid<=1;keep_slot<=current_track[1:0];
      end
     end else if(!cache_ready)begin
      if(manual_request&&manual_found)
       begin pend_valid<=1;pend_track<=manual_target;pend_view<=thumbnail;pend_sel<=1;end
      else if(view_request&&view_select)
       begin pend_valid<=1;pend_track<=focused_track;pend_view<=target_view;pend_sel<=1;end
     end
    end
    BLACK:if(fade_black)begin
     mark_pending<=0;   // 新路由清掉上一页的补记挂起
     thumbnail<=requested_view;
     if(pending_track[3:2]!=cache_page)begin
      audio_allowed<=0;same_page_wait<=0;
      if(!page_issued)page_start<=1;  // 串行兜底：目标槽==显示槽时受理拍未预发
      page_issued<=0;keep_valid<=0;state<=PAGE;
     end else if(page_valid[pending_track[1:0]])begin
      cover_select<=1;state<=ACK_START;
     end else begin
      // 同页目标槽后台未载完：进PAGE只等该槽，不重载整页、不停当前音频
      same_page_wait<=1;state<=PAGE;
     end
    end
    PAGE:begin
     if(target_loaded&&page_valid[pending_track[1:0]])begin
      // 选中槽已就绪：整页未载完也先放行出图，其余槽后台补齐
      mark_pending<=1;same_page_wait<=0;cover_select<=1;state<=ACK_START;
     end else if((cache_done&&target_loaded)||(same_page_wait&&cache_ready))begin
      // 选中槽缺失/失败（或与其余槽同时完成），或等同页槽时后台已结束：按原逻辑兜底
      for(j=0;j<4;j=j+1)
       if(!cache_complete[j])bad_covers[{cache_page,j[1:0]}]<=1;
      if(page_valid!=0)begin
       if(!page_valid[pending_track[1:0]])pending_track<={cache_page,first_slot};
       cover_select<=1;state<=ACK_START;
      end else begin
       // 整页失败：清锁存，交给自动跳歌决定去向，避免补发劫持abort语义
       current_track<=pending_track;abort_toggle<=~abort_toggle;
       load_failed<=1;state<=IDLE;pend_valid<=0;
      end
     end
    end
    ACK_START:if(control_busy)state<=ACK_END;
    ACK_END:if(!control_busy)begin
     current_track<=pending_track;audio_allowed<=1;state<=IDLE;
    end
    default:state<=BOOT;
   endcase
  end
 end
endmodule
