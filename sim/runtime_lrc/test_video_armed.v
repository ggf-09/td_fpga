`timescale 1ns/1ps
// 顶层"显示解锁"逻辑（video_armed_fragment，prepare脚本从top_tf_hdmi_audio.v原样抽取）。
// 解锁条件=audio_allowed && image_complete[当前显示槽]：提前放行选中槽一就绪就重新出图，
// 不再等sd_free（整页载完）。旧写法用sd_free门控，把跨页提前放行屏蔽到页末——
// 实机表现为跨页黑屏约2秒、封面与音乐同来（2026-10-26根因）。
module test_video_armed;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,abort_toggle=0,audio_allowed=0,frame_start=0,commit=0;
 reg [3:0] image_complete=0,pending_track=0;reg [1:0] active_index=0;
 wire [3:0] track_pix;wire abort_pulse,armed;
 video_armed_fragment dut(.video_clk(clk),.video_rst(rst),
  .library_abort_toggle(abort_toggle),.library_audio_allowed(audio_allowed),
  .loader_image_complete(image_complete),.active_index_pix(active_index),
  .frame_start_raw(frame_start),.index_commit_pix(commit),.library_pending_track(pending_track),
  .library_track_pix(track_pix),.library_abort_pulse(abort_pulse),.library_video_armed(armed));
 task frame;begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;repeat(2)@(negedge clk);
  if(armed)$fatal(1,"armed out of reset");
  // 上电：音画放行+当前显示槽就绪 → 帧边界后解锁
  audio_allowed=1;image_complete=4'b0001;active_index=0;
  repeat(3)@(negedge clk);frame();frame();
  if(!armed)$fatal(1,"not armed with audio allowed and active slot complete");
  // 跨页开始：audio_allowed撤下 → 无需帧边界即撤防（黑屏掩护加载）
  audio_allowed=0;repeat(4)@(negedge clk);
  if(armed)$fatal(1,"stayed armed without audio_allowed");
  // 关键回归：提前放行时刻——整页未载完（本fragment根本没有sd_free输入），
  // 仅"当前显示槽就绪+音画放行"就必须重新解锁；旧的sd_free门控在这里永远解不了
  audio_allowed=1;image_complete=4'b0010;active_index=1;
  repeat(3)@(negedge clk);frame();frame();
  if(!armed)$fatal(1,"early-release re-arm blocked (old sd_free gating regression)");
  // 当前显示槽失效（被清/未完成）→ 撤防，即使其它槽已就绪
  image_complete=4'b0000;repeat(4)@(negedge clk);
  if(armed)$fatal(1,"stayed armed with active slot incomplete");
  image_complete=4'b1101;active_index=1;      // 槽1仍未就绪，其它槽都就绪
  repeat(3)@(negedge clk);frame();frame();
  if(armed)$fatal(1,"armed on non-active slot completion");
  // 槽1补齐 → 解锁恢复
  image_complete=4'b1111;repeat(3)@(negedge clk);frame();frame();
  if(!armed)$fatal(1,"re-arm after slot completion failed");
  // abort链路：toggle→挂起→帧边界出单拍pulse，track_pix随后更新
  pending_track=9;abort_toggle=1;repeat(4)@(negedge clk);
  if(abort_pulse)$fatal(1,"abort pulse before frame boundary");
  frame();
  if(!abort_pulse)$fatal(1,"abort pulse missing at frame boundary");
  @(negedge clk);
  if(abort_pulse)$fatal(1,"abort pulse wider than one cycle");
  if(track_pix!=9)$fatal(1,"track_pix not updated by abort");
  // commit链路：正常提交更新track_pix
  pending_track=6;commit=1;@(negedge clk);commit=0;@(negedge clk);
  if(track_pix!=6)$fatal(1,"track_pix not updated by commit");
  $display("PASS video armed: arm needs audio_allowed && active-slot complete (no sd_free), disarm immediate, abort/commit track latch");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
