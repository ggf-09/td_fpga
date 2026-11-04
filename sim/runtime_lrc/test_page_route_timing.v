`timescale 1ns/1ps
// 端到端时序：真实 library_page_router + cover_page_controller + 加载器SEQ FSM
// （menu_boot_fragment，从sd_card_bmp.v抽取），扫描器和SD逐文件加载用带延迟的
// 行为模型。验证跨页路由的提前放行在真实流水线时序下确实在"选中槽落地"即放行
// （封面select前只加载了1张），而不是等整页4张载完；以及后台期跨页请求锁存
// 在page_done后自动补发。SCAN/COVER比例约1:5，接近真实（目录扫描远小于1.44MB读卡）。
// 重叠加载：目标槽≠显示槽时受理拍即发page_start（与淡出并行）并keep显示槽
// （其image_complete在整页失效时保留，旧封面平滑淡出）；目标槽==显示槽走串行兜底。
module test_page_route_timing;
 localparam SCAN=200,COVER=1000;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;
 // ---- router <-> controller/fragment/模型 互连 ----
 wire [1:0] cache_page;           // controller active_page
 reg  [3:0] image_complete=0;     // loader模型
 wire [3:0] cache_complete=image_complete;          // 卡上16首全有song_valid，等价
 wire frag_sd_free,ctrl_reloading;
 wire cache_ready=frag_sd_free&&!ctrl_reloading;
 wire page_done,page_start;wire [1:0] target_page,cover_slot;
 reg manual_request=0,manual_found=1;reg [3:0] manual_target=0;
 reg fade_busy=0,fade_black=0,control_busy=0;
 wire route_busy,audio_allowed,fade_request,cover_select,manual_accepted;
 wire [3:0] current_track,pending_track;
 wire keep_valid;wire [1:0] keep_slot;
 // page_start在重叠路径下受理拍即发（等不到fade_black）；keep_*在invalidate时快照
 reg page_started=0,keep_seen=0;reg [1:0] keep_at_inv=0;
 library_page_router #(.BROWSE_PAGING(1)) u_router(
  .clk(clk),.rst_n(rst_n),.catalog_playable(16'hffff),
  .cache_page(cache_page),.cache_complete(cache_complete),
  .cache_ready(cache_ready),.cache_done(page_done),
  .manual_request(manual_request),.manual_found(manual_found),.manual_target(manual_target),
  .auto_request(1'b0),.auto_target(4'd0),
  .view_request(1'b0),.view_select(1'b0),.target_view(1'b0),
  .focus_slot(2'd0),.focus_page(2'd0),
  .fade_busy(fade_busy),.fade_black(fade_black),.control_busy(control_busy),
  .route_busy(route_busy),.sequence_ready(),.playable(),
  .current_track(current_track),.pending_track(pending_track),
  .audio_allowed(audio_allowed),.thumbnail(),
  .fade_request(fade_request),.cover_select(cover_select),.cover_slot(cover_slot),
  .page_start(page_start),.target_page(target_page),
  .manual_accepted(manual_accepted),.manual_same(),.load_failed(),.abort_toggle(),
  .keep_valid(keep_valid),.keep_slot(keep_slot));
 // ---- 真实页控制器 ----
 wire catalog_start,cache_invalidate;wire [1:0] catalog_page;
 reg metadata_done=0;
 cover_page_controller u_ctrl(
  .clk(clk),.rst_n(rst_n),.init_ready(1'b1),
  .reload_request(page_start),.requested_page(target_page),
  .sector_busy(1'b0),.cache_done(frag_sd_free),
  .metadata_done(metadata_done),.metadata_page(catalog_page),
  .reloading(ctrl_reloading),.quiescing(),.cache_invalidate(cache_invalidate),
  .catalog_start(catalog_start),.catalog_page(catalog_page),.active_page(cache_page),
  .page_done(page_done));
 always @(posedge clk)if(page_start)page_started<=1;
 always @(posedge clk)if(cache_invalidate)begin keep_seen<=keep_valid;keep_at_inv<=keep_slot;end
 // ---- 真实加载器SEQ FSM（fragment） ----
 reg scan_done_latched=0;
 reg loader_load_done=0;
 wire load_start,load_menu;wire [1:0] load_image_index;wire [31:0] load_cluster,load_file_size;
 menu_boot_fragment u_seq(
  .clk(clk),.rst(!rst_n),.sd_init_done(1'b1),.cache_invalidate(cache_invalidate),
  .scan_done_latched(scan_done_latched),.scan_valid_latched(4'b1111),
  .scanner_menu_valid(1'b1),.scanner_menu_cluster(32'd901),.scanner_menu_size(32'd921654),
  .requested_slot(cover_slot),
  .loader_load_done(loader_load_done),.loader_memory_error(8'd0),
  .streamer_file_done(1'b0),.streamer_fs_error(8'd0),.streamer_byte_valid(1'b0),
  .decoder_scale_complete(1'b1),.decoder_header_error(1'b0),.decoder_dims_valid(1'b1),
  .decoder_width_bcd(16'h0640),.decoder_height_bcd(16'h0480),
  .menu_ready(),.load_menu(load_menu),.load_start(load_start),.load_image_index(load_image_index),
  .load_cluster(load_cluster),.load_file_size(load_file_size),.load_abort(),
  .frame_commit(),.decode_error(),.sd_free(frag_sd_free));
 // ---- 扫描器行为模型：catalog_start后SCAN拍给出metadata_done ----
 integer scan_count=0;
 always @(posedge clk)begin
  metadata_done<=0;
  if(catalog_start)scan_count<=SCAN;
  else if(scan_count>0)begin
   scan_count<=scan_count-1;
   if(scan_count==1)begin metadata_done<=1;scan_done_latched<=1;end
  end
  if(cache_invalidate)scan_done_latched<=0;
 end
 // ---- 加载行为模型：load_start后COVER拍置done和image_complete[槽] ----
 // 与真实loader一致：invalidate清完成位但保留keep_slot槽（旧封面靠它平滑淡出）；
 // 每个槽load_start时先清本槽位（keep槽在其轮到重写时才让位）。
 integer load_count=0;reg [1:0] cur_slot=0;reg cur_menu=0;
 integer loads_this_page=0;
 reg [1:0] first_slot_of_page=0;
 wire [3:0] keep_mask=keep_valid?(4'b0001<<keep_slot):4'b0000;
 always @(posedge clk)begin
  loader_load_done<=0;
  if(cache_invalidate)begin image_complete<=image_complete&keep_mask;loads_this_page<=0;end
  if(load_start)begin
   load_count<=load_menu?50:COVER;cur_slot<=load_image_index;cur_menu<=load_menu;
   if(!load_menu)begin
    image_complete[load_image_index]<=0;
    loads_this_page<=loads_this_page+1;
    if(loads_this_page==0)first_slot_of_page<=load_image_index;
   end
  end else if(load_count>0)begin
   load_count<=load_count-1;
   if(load_count==1)begin
    loader_load_done<=1;
    if(!cur_menu)image_complete[cur_slot]<=1;
   end
  end
 end
 // ---- 转场/ACK行为模型（同test_library_router） ----
 // fade_request是受理拍单拍脉冲，断言消耗半拍后black()可能错过其尾巴——粘滞捕获
 reg fade_req_seen=0;
 always @(posedge clk)if(fade_request)fade_req_seen<=1;
 task black;begin
  if(!fade_req_seen)wait(fade_request);
  fade_req_seen=0;
  @(negedge clk);fade_busy=1;
  repeat(4)@(negedge clk);fade_black=1;@(negedge clk);fade_black=0;
 end endtask
 task ack;begin
  wait(cover_select);@(negedge clk);control_busy=1;
  repeat(4)@(negedge clk);control_busy=0;repeat(3)@(negedge clk);
  if(!audio_allowed||route_busy)$fatal(1,"audio not released after cover ACK");
 end endtask
 // 封面select时已加载的张数：提前放行=1，等整页=4
 integer covers_at_select=0;
 always @(posedge clk)if(cover_select)covers_at_select<=loads_this_page;
 task press;input [3:0] t;begin
  manual_target=t;manual_request=1;@(negedge clk);manual_request=0;
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;scan_done_latched=1;   // 上电首轮：目录已扫完
  wait(cache_ready);repeat(2)@(negedge clk);
  ack();fade_busy=0;                                      // BOOT选中track0
  if(current_track!=0)$fatal(1,"boot wrong");
  // 场景1：跨页 0->4（page1 slot0，与显示槽同号）：串行兜底——受理拍不得预发，
  // fade_black才发page_start、不keep显示槽；提前放行仍应在第1张落地即出图。
  page_started=0;
  press(4);@(negedge clk);
  if(page_started)$fatal(1,"slot-equal cross-page must stay serial (no overlap)");
  black();@(negedge clk);   // 串行page_start在fade_black当拍发，下一拍粘滞才可见
  if(!page_started||target_page!=1||audio_allowed)$fatal(1,"cross-page route wrong");
  ack();fade_busy=0;
  repeat(3)@(negedge clk);
  if(keep_seen)$fatal(1,"serial route must not keep the display slot");
  if(current_track!=4||cover_slot!=0)$fatal(1,"cross-page track wrong");
  if(first_slot_of_page!==0)$fatal(1,"slot0 target should load slot0 first, got %0d",first_slot_of_page);
  if(covers_at_select!=1)$fatal(1,"early release did not fire: %0d covers loaded before select",covers_at_select);
  // 场景2：等整页载完后跨页回 4->3（page0 slot3≠显示槽0）：重叠——受理拍即发page_start、
  // fade_black前音频不断，invalidate保留显示槽0（旧封面平滑淡出）；轮转slot3先载、1张即放行。
  wait(cache_ready);repeat(4)@(negedge clk);
  page_started=0;
  press(3);@(negedge clk);
  if(!page_started||target_page!=0)$fatal(1,"overlap page_start missing at accept");
  if(!audio_allowed)$fatal(1,"audio stopped before fade black");
  black();
  // keep检查必须在ack()前：ack返回时keep槽的轮到重写已开始（其bit被合法清掉）
  if(!keep_seen||keep_at_inv!=0)$fatal(1,"overlap did not keep display slot 0 at invalidate");
  if(image_complete[0]!==1'b1)$fatal(1,"keep slot cleared at invalidate: fade-out would be masked black");
  ack();fade_busy=0;
  if(current_track!=3||cover_slot!=3)$fatal(1,"second cross-page track wrong");
  if(first_slot_of_page!==3)$fatal(1,"rotation broken: slot3 target loaded slot %0d first",first_slot_of_page);
  if(covers_at_select!=1)$fatal(1,"early release did not fire on rotated slot: %0d covers",covers_at_select);
  // 场景3：后台加载期间跨页请求应锁存，page_done后自动补发（重叠+keep当前显示槽3），
  // 新页仍1张即放行。此刻page0后台仍在加载（只载了1张）。
  press(6);                                               // page1 slot2，跨页
  if(manual_accepted||fade_request)$fatal(1,"cross-page request served mid-background");
  repeat(4)@(negedge clk);
  if(!u_router.pend_valid)$fatal(1,"cross-page request not latched");
  page_started=0;
  wait(page_done);                                        // 后台整页载完
  black();                                                // 锁存自动补发
  if(!page_started||target_page!=1||audio_allowed)$fatal(1,"latched fire wrong");
  // 同场景2：keep检查必须在ack()前（keep槽3是轮转第2个，ack返回时已轮到它重写）
  if(!keep_seen||keep_at_inv!=3)$fatal(1,"latched overlap keep wrong (display slot 3)");
  if(image_complete[3]!==1'b1)$fatal(1,"latched route: keep slot cleared at invalidate");
  ack();fade_busy=0;
  if(current_track!=6||cover_slot!=2)$fatal(1,"latched route track wrong");
  if(first_slot_of_page!==2)$fatal(1,"latched route lost priority rotation");
  if(covers_at_select!=1)$fatal(1,"latched route lost early release: %0d covers",covers_at_select);
  $display("PASS page route timing: early release at 1 cover on serial/overlap/latched cross-page routes, display-slot keep survives invalidate, slot-equal stays serial");$finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
