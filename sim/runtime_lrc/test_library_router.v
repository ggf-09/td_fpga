`timescale 1ns/1ps
module test_library_router;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;
 reg [15:0] catalog_playable=16'hffff;
 reg [1:0] cache_page=0;
 reg [3:0] cache_complete=15;
 reg cache_ready=0,cache_done=0,manual_request=0,manual_found=1,auto_request=0;
 reg [3:0] manual_target=0,auto_target=0;
 reg view_request=0,view_select=0,target_view=0;
 reg [1:0] focus_slot=0;
 reg fade_busy=0,fade_black=0,control_busy=0;
 wire route_busy,sequence_ready,audio_allowed,thumbnail,fade_request,cover_select,page_start;
 wire [15:0] playable;
 wire [3:0] current_track,pending_track;
 wire [1:0] cover_slot,target_page;
 wire manual_accepted,manual_same,load_failed,abort_toggle;
 wire keep_valid;wire [1:0] keep_slot;
 // page_start粘滞捕获：重叠加载下page_start在受理拍即发（等不到fade_black），
 // 串行兜底下仍在BLACK发出；keep_*在page_start同拍快照供两种路径分别断言
 reg page_started=0,keep_at_start=0;reg [1:0] keep_slot_at_start=0;
 always@(posedge clk)if(page_start)begin
  page_started<=1;keep_at_start<=keep_valid;keep_slot_at_start<=keep_slot;
 end
 library_page_router dut(.focus_page(2'b00),.*);
 // fade_request同样是受理拍单拍脉冲，断言消耗半拍后black()可能错过其尾巴——粘滞捕获
 reg fade_req_seen=0;
 always@(posedge clk)if(fade_request)fade_req_seen<=1;
 task ack;
 begin
  wait(cover_select);@(negedge clk);control_busy=1;
  repeat(4)@(negedge clk);
  if(!route_busy)$fatal(1,"route ended before video ACK");
  control_busy=0;repeat(3)@(negedge clk);
  if(!audio_allowed||route_busy)$fatal(1,"audio not released after cover ACK");
 end
 endtask
 task black;
 begin
  if(!fade_req_seen)wait(fade_request);
  fade_req_seen=0;
  @(negedge clk);fade_busy=1;
  repeat(4)@(negedge clk);fade_black=1;@(negedge clk);fade_black=0;
 end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;cache_ready=1;ack();
  if(current_track!=0)$fatal(1,"boot selection wrong");
  // Cross-page manual selection uses same physical slot but a new identity.
  // 目标槽==当前显示槽（0->4都是slot0）：走串行兜底，受理拍不得预发page_start
  page_started=0;keep_at_start=0;
  manual_target=4;manual_request=1;@(negedge clk);manual_request=0;
  if(!manual_accepted||manual_same)$fatal(1,"manual selection acceptance wrong");
  @(negedge clk);
  if(page_started)$fatal(1,"slot-equal cross-page must stay serial (no early page_start)");
  black();
  if(!page_start||target_page!=1||audio_allowed||cover_select)$fatal(1,"cross-page route did not stop audio and reload");
  if(keep_at_start)$fatal(1,"serial fallback must not keep the display slot");
  cache_ready=0;repeat(10)@(negedge clk);
  if(cover_select||audio_allowed)$fatal(1,"old cache used during page load");
  cache_page=1;cache_done=1;cache_ready=1;@(negedge clk);cache_done=0;ack();fade_busy=0;
  if(current_track!=4||cover_slot!=0)$fatal(1,"same-slot cross-page track identity lost");
  // View-only transition keeps current music and changes thumbnail layout.
  view_request=1;target_view=1;@(negedge clk);view_request=0;black();
  if(page_start||!thumbnail||!audio_allowed)$fatal(1,"view toggle unnecessarily reloads page/audio");
  ack();fade_busy=0;
  // Failed cover on next page: fall back to a playable loaded slot.
  auto_request=1;auto_target=10;@(negedge clk);auto_request=0;black();
  cache_page=2;cache_complete=4'b0010;cache_done=1;@(negedge clk);cache_done=0;ack();fade_busy=0;
  if(current_track!=9||playable[10]||playable[8]||!playable[9])$fatal(1,"failed cover not excluded or fallback wrong");
  // Entire failed page releases the fade and reports failure for auto-skip.
  manual_target=15;manual_request=1;@(negedge clk);manual_request=0;black();
  cache_page=3;cache_complete=0;cache_done=1;@(negedge clk);cache_done=0;
  if(!load_failed||!abort_toggle||route_busy||audio_allowed||playable[15:12]!=0)
   $fatal(1,"fully failed page deadlocks or reuses stale audio");
  fade_busy=0;
  // Priority early-exit: the selected slot alone releases the route before
  // page_done; missing siblings are excluded when the run later completes.
  manual_target=6;manual_request=1;@(negedge clk);manual_request=0;black();
  cache_ready=0;repeat(4)@(negedge clk);
  // Stale page metadata must not trigger a false release even if the same
  // slot number happens to be complete on the old page.
  cache_page=2;cache_complete=4'b0100;repeat(4)@(negedge clk);
  if(cover_select||audio_allowed)$fatal(1,"stale page released the route early");
  // New page metadata: only slot 2 loaded, no page_done pulse yet.
  // ack() waits on cover_select; if the router still waited for page_done
  // this would hang and trip the global timeout instead.
  cache_page=1;ack();fade_busy=0;
  if(current_track!=6||cover_slot!=2)$fatal(1,"early release track identity wrong");
  // The rest of the page finishes later with slots 0 and 3 missing.
  cache_complete=4'b0110;cache_done=1;cache_ready=1;@(negedge clk);cache_done=0;repeat(2)@(negedge clk);
  if(playable[4]||!playable[5]||!playable[6]||playable[7])
   $fatal(1,"deferred bad-cover marking wrong after priority release");
  // A later same-page selection is unaffected by the deferred marking path.
  manual_target=5;manual_request=1;@(negedge clk);manual_request=0;black();ack();fade_busy=0;
  if(current_track!=5)$fatal(1,"same-page selection after early release broken");
  // ---- Background-load window: router stays responsive to same-page work ----
  // Cross into page 2 (track 8) with priority early release; background keeps loading.
  // 目标槽0≠当前显示槽1：受理拍即重叠发出page_start（等不到fade_black），并keep显示槽1
  page_started=0;keep_at_start=0;
  manual_target=8;manual_request=1;@(negedge clk);manual_request=0;
  if(!manual_accepted)$fatal(1,"overlap cross-page not accepted");
  @(negedge clk);
  if(!page_started||target_page!=2)$fatal(1,"overlap cross-page did not start loading at accept");
  if(!keep_at_start||keep_slot_at_start!=1)$fatal(1,"overlap keep slot wrong");
  black();
  if(audio_allowed)$fatal(1,"cross-page into page 2 kept audio during reload");
  cache_ready=0;repeat(4)@(negedge clk);
  cache_page=2;cache_complete=4'b0001;ack();fade_busy=0;   // slot 0 done -> early release
  if(current_track!=8)$fatal(1,"early release into page 2 wrong");
  // Cross-page request during background: not served now, but latched (no lost press).
  manual_target=0;manual_request=1;@(negedge clk);
  if(manual_accepted||fade_request||route_busy)$fatal(1,"cross-page request served mid-background");
  manual_request=0;repeat(2)@(negedge clk);
  if(!dut.pend_valid)$fatal(1,"cross-page request during background not latched");
  // Pure view toggle (opening the browser) is accepted during background and does
  // NOT cancel the queued track change.
  view_request=1;target_view=1;view_select=0;@(negedge clk);view_request=0;
  black();ack();fade_busy=0;
  if(page_start||!audio_allowed||current_track!=8)$fatal(1,"view toggle during background broke route");
  if(!dut.pend_valid)$fatal(1,"view toggle cancelled the queued track change");
  // Same-page request for a slot still loading: accepted, waits in PAGE without
  // touching audio or restarting the page, releases when the slot lands.
  manual_target=10;manual_request=1;@(negedge clk);
  if(!manual_accepted)$fatal(1,"same-page request during background not accepted");
  manual_request=0;black();
  if(page_start||!audio_allowed)$fatal(1,"same-page slot wait reloaded page or killed audio");
  repeat(4)@(negedge clk);
  if(cover_select)$fatal(1,"same-page wait released before its slot was loaded");
  cache_complete=4'b0101;ack();fade_busy=0;                 // slot 2 lands -> release
  if(current_track!=10||cover_slot!=2)$fatal(1,"same-page slot wait release wrong");
  // The served selection is the latest intent: it clears the queued track change.
  if(dut.pend_valid)$fatal(1,"served selection did not clear the queue");
  // Deferred marking still applies to the run that was in flight.
  // (Tracks 8/10/11 were already bad-marked by the earlier failed-cover scenario;
  //  this run newly marks track 9 whose slot never completed.)
  cache_done=1;cache_ready=1;@(negedge clk);cache_done=0;repeat(2)@(negedge clk);
  if(playable[9]||playable[11])
   $fatal(1,"deferred marking wrong after same-page wait");
  // Same-page request for an already-loaded slot during background: immediate.
  // (page 3 slots were all marked bad by the failed-page scenario; use page 1.)
  // 目标槽1≠当前显示槽2：重叠发出
  page_started=0;keep_at_start=0;
  manual_target=5;manual_request=1;@(negedge clk);manual_request=0;
  if(!manual_accepted)$fatal(1,"overlap cross-page back to page 1 not accepted");
  @(negedge clk);
  if(!page_started||target_page!=1)$fatal(1,"overlap cross-page back to page 1 missing at accept");
  if(!keep_at_start||keep_slot_at_start!=2)$fatal(1,"overlap keep slot back to page 1 wrong");
  black();
  cache_ready=0;repeat(4)@(negedge clk);
  cache_page=1;cache_complete=4'b0110;ack();fade_busy=0;    // early release slot 1
  if(current_track!=5)$fatal(1,"early release back to page 1 wrong");
  manual_target=6;manual_request=1;@(negedge clk);          // slot 2 already loaded
  if(!manual_accepted)$fatal(1,"same-page loaded slot during background not accepted");
  manual_request=0;black();ack();fade_busy=0;               // no wait: ack() returns at once
  if(page_start||current_track!=6)$fatal(1,"same-page loaded slot took the wait path");
  // Defensive escape: waiting on a slot when the run has ended without page_done.
  manual_target=7;manual_request=1;@(negedge clk);          // slot 3 still missing
  if(!manual_accepted)$fatal(1,"same-page missing slot during background not accepted");
  manual_request=0;black();
  repeat(4)@(negedge clk);
  if(cover_select)$fatal(1,"missing slot released without load");
  cache_ready=1;ack();fade_busy=0;                          // run over, no page_done pulse
  if(current_track!=5||cover_slot!=1)$fatal(1,"slot-wait escape fallback wrong");
  if(!playable[5]||!playable[6]||playable[7])
   $fatal(1,"slot-wait escape marking wrong");
  // Latched cross-page request fires automatically when the background run ends.
  // 目标槽1==当前显示槽1（track5->track9）：串行兜底，受理拍不得预发
  page_started=0;keep_at_start=0;
  manual_target=9;manual_request=1;@(negedge clk);manual_request=0;
  if(!manual_accepted)$fatal(1,"slot-equal latch-fire candidate not accepted");
  @(negedge clk);
  if(page_started)$fatal(1,"slot-equal latch-fire candidate must stay serial");
  black();
  if(!page_start||target_page!=2)$fatal(1,"cross-page into page 2 for latch-fire wrong");
  if(keep_at_start)$fatal(1,"slot-equal route must not keep the display slot");
  cache_ready=0;repeat(4)@(negedge clk);
  cache_page=2;cache_complete=4'b0010;ack();fade_busy=0;    // early release slot 1
  if(current_track!=9)$fatal(1,"early release for latch-fire wrong");
  manual_target=3;manual_request=1;@(negedge clk);          // page 0: latched, not served
  if(manual_accepted||fade_request||route_busy)$fatal(1,"latch candidate served mid-background");
  manual_request=0;repeat(2)@(negedge clk);
  if(!dut.pend_valid)$fatal(1,"second cross-page request not latched");
  page_started=0;keep_at_start=0;
  cache_complete=4'b1111;cache_done=1;cache_ready=1;@(negedge clk);cache_done=0;
  black();                                                  // latch fires on its own
  // 补发同样走重叠：page_start在补发拍已发出，并keep补发时的显示槽（track9=slot1）
  if(!page_started||target_page!=0||audio_allowed)$fatal(1,"latched request fired wrong");
  if(!keep_at_start||keep_slot_at_start!=1)$fatal(1,"latched fire keep slot wrong");
  if(dut.pend_valid)$fatal(1,"latch not cleared by firing");
  cache_ready=0;repeat(4)@(negedge clk);
  cache_page=0;cache_complete=4'b1000;ack();fade_busy=0;    // slot 3 done -> early release
  if(current_track!=3||cover_slot!=3)$fatal(1,"latched request route wrong");
  $display("PASS library router: boot, same-slot cross-page, video ACK, view-only, cover fallback, failed-page escape, priority early release with deferred bad marking, background-window same-page accept/wait/release/escape, cross-page queue fire with latest-intent clear, overlapped page_start with display-slot keep vs slot-equal serial fallback");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
