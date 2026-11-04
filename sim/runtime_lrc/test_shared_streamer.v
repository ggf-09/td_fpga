`timescale 1ns/1ps
// 集成测试：sd_card_bmp 内共享流读器的 owner 复用逻辑（与生产代码逐行一致）
// 验证 cover(0) -> lyric(1) -> wav(2) -> lyric(1) -> wav(2) 切换链各客户端字节完整。
module test_shared_streamer;
  reg clk=0; always #5 clk=~clk;
  reg rst=1;
  // ---- 客户端激励 ----
  reg sd_free=0, lyric_sector_mode=0, wav_play_en=0;
  reg load_start=0, lyric_file_start=0, wav_file_start=0;
  reg load_abort=0, cache_invalidate=0, wav_can_read_sector=1;
  reg [31:0] load_cluster=0, load_file_size=0;
  reg [31:0] lyric_first_cluster=0, lyric_file_size=0,lyric_start_offset=0;
 reg lyric_file_partial=0;
  reg [31:0] wav_first_cluster=0, wav_file_size=0, wav_start_offset=0;
  // ---- 扇区响应模型 ----
  reg arb_sector_busy=0, arb_sector_valid=0, arb_sector_done=0;
  reg [7:0] arb_sector_byte=0, arb_sector_error=0;
  reg [8:0] arb_sector_byte_index=0;
  wire streamer_sector_req;
  wire [31:0] streamer_sector_lba;

  // ===== 以下与 sd_card_bmp.v 生产代码逐行一致（owner/复位/分发） =====
wire [1:0] stream_owner = !sd_free ? 2'd0 : lyric_sector_mode ? 2'd1 : 2'd2;
reg  [1:0] stream_owner_q;
always @(posedge clk or posedge rst) begin
    if (rst) stream_owner_q <= 2'd0;
    else     stream_owner_q <= stream_owner;
end
wire stream_owner_switch = (stream_owner != stream_owner_q);
wire shared_rst_n = ~rst && !stream_owner_switch &&
                    (stream_owner == 2'd2 ? wav_play_en :
                     stream_owner == 2'd0 ? !(load_abort | cache_invalidate) : 1'b1);

wire        shared_file_start = stream_owner == 2'd0 ? load_start :
                                stream_owner == 2'd1 ? lyric_file_start : wav_file_start;
wire [31:0] shared_first_cluster = stream_owner == 2'd0 ? load_cluster :
                                   stream_owner == 2'd1 ? lyric_first_cluster : wav_first_cluster;
wire [31:0] shared_file_size = stream_owner == 2'd0 ? load_file_size :
                               stream_owner == 2'd1 ? lyric_file_size : wav_file_size;
wire [31:0] shared_start_offset = stream_owner == 2'd2 ? wav_start_offset :
                                         stream_owner == 2'd1 ? lyric_start_offset : 32'd0;

wire        shared_file_busy;
wire        shared_file_done;
wire        shared_file_valid;
wire [7:0]  shared_file_byte;
wire [31:0] shared_file_offset;
wire [7:0]  shared_fs_error;

fat32_file_streamer #(.MAX_VISITED_CLUSTERS(65535),.SEEK_SUPPORT(1),.RANGE_SUPPORT(1)) u_streamer (
    .clk                 (clk),
    .rst_n               (shared_rst_n),
    .file_start          (shared_file_start),
    .start_offset        (shared_start_offset),
    .file_partial        (stream_owner == 2'd1 && lyric_file_partial),
    .first_cluster       (shared_first_cluster),
    .file_size           (shared_file_size),
    .sectors_per_cluster (8'd4),
    .fat_start_lba       (32'd1),
    .data_start_lba      (32'd100),
    .max_cluster         (32'd1000),
    .file_busy           (shared_file_busy),
    .file_done           (shared_file_done),     // 源文件读取完成（含出错完成）
    .file_valid          (shared_file_valid),
    .file_byte           (shared_file_byte),
    .file_byte_offset    (shared_file_offset),
    .fs_error            (shared_fs_error),
    .sector_req          (streamer_sector_req),
    .sector_lba          (streamer_sector_lba),
    // WAV客户端额外叠加FIFO扇区级背压；流读器只在持有仲裁器时运行，
    // 返回信号无需再按owner门控（与合并前封面客户端的处理一致）。
    .sector_busy         (arb_sector_busy || (stream_owner == 2'd2 && !wav_can_read_sector)),
    .sector_valid        (arb_sector_valid),
    .sector_byte         (arb_sector_byte),
    .sector_byte_index   (arb_sector_byte_index),
    .sector_done         (arb_sector_done),
    .sector_error        (arb_sector_error)
);

// 输出按owner分发：非持有方客户端被各自复位/状态机关断，不会误采样
  wire arb_sector_req=streamer_sector_req;
  wire [31:0] arb_sector_lba=streamer_sector_lba;
  wire streamer_file_done  = stream_owner == 2'd0 && shared_file_done;
  wire streamer_byte_valid = stream_owner == 2'd0 && shared_file_valid;
  wire [7:0] streamer_byte = shared_file_byte;
  wire wav_file_busy  = stream_owner == 2'd2 && shared_file_busy;
  wire wav_file_done  = stream_owner == 2'd2 && shared_file_done;
  wire wav_file_valid = stream_owner == 2'd2 && shared_file_valid;
  wire [7:0] wav_file_byte = shared_file_byte;
  wire [31:0] wav_file_offset = shared_file_offset;
  wire lyric_file_done  = stream_owner == 2'd1 && shared_file_done;
  wire lyric_file_valid = stream_owner == 2'd1 && shared_file_valid;
  wire [7:0] lyric_file_byte = shared_file_byte;
  wire [31:0] lyric_file_offset = shared_file_offset;

  // ===== 虚拟盘：FAT@LBA1，数据区@LBA100，spc=4 =====
  // 文件A(封面):簇10-11链，3000字节；文件B(封面):簇12-13链，3000字节
  // 字体:簇20，500字节；歌词:簇22，200字节；WAV:簇30-32链，8000字节
  function [31:0] fat_next(input [31:0] cl);
    begin
      case (cl)
        10: fat_next=11; 11: fat_next=32'h0fffffff;
        12: fat_next=13; 13: fat_next=32'h0fffffff;
        20: fat_next=32'h0fffffff; 22: fat_next=32'h0fffffff;
        30: fat_next=31; 31: fat_next=32; 32: fat_next=33; 33: fat_next=32'h0fffffff;
        default: fat_next=32'h0fffffff;
      endcase
    end
  endfunction
  // 扇区字节内容：数据区= lba/n 的可预测图案，用于完整性校验
  integer n;
  reg [31:0] req_lba;
  task serve_sector;
    begin
      @(negedge clk);
      arb_sector_busy=1;
      @(negedge clk);
      for(n=0;n<512;n=n+1) begin
        arb_sector_valid=1; arb_sector_byte_index=n[8:0];
        arb_sector_byte = (req_lba==1) ? 8'hAA : (req_lba[7:0] ^ n[7:0]);
        @(negedge clk);
      end
      arb_sector_valid=0; arb_sector_done=1;
      @(negedge clk); arb_sector_done=0; arb_sector_busy=0;
    end
  endtask
  // FAT扇区内容需在 req_lba==1 时给出链值——改用组合覆盖：
  // 为简化，FAT扇区字节在for循环内由fat_next查表生成
  // （上面的 8'hAA 仅占位，实际由下方独立模型驱动）

  // 独立扇区服务进程（支持FAT查表）
  reg [31:0] fat_entry;
  initial forever begin
    @(negedge clk);
    if (arb_sector_req && !arb_sector_busy) begin
      req_lba=arb_sector_lba;
      arb_sector_busy=1;
      @(negedge clk);
      for(n=0;n<512;n=n+1) begin
        arb_sector_valid=1; arb_sector_byte_index=n[8:0];
        if (req_lba==1) begin
          // FAT扇区：条目c在字节4c..4c+3（小端）
          fat_entry = fat_next(n/4);
          case (n%4)
            0: arb_sector_byte = fat_entry[7:0];
            1: arb_sector_byte = fat_entry[15:8];
            2: arb_sector_byte = fat_entry[23:16];
            3: arb_sector_byte = fat_entry[31:24];
          endcase
        end else begin
          arb_sector_byte = req_lba[7:0] ^ n[7:0];
        end
        @(negedge clk);
      end
      arb_sector_valid=0; arb_sector_done=1;
      @(negedge clk); arb_sector_done=0; arb_sector_busy=0;
    end
  end

  // ===== 状态追踪 =====
  reg [3:0] prev_state=0;
  always @(posedge clk) begin
    if(shared_file_valid && shared_file_byte !==
       (((100+(shared_first_cluster-2)*4+(shared_file_offset/512))%256) ^ (shared_file_offset%256)))
      $fatal(1,"shared owner%0d byte%0d payload mismatch",stream_owner,shared_file_offset);
    if(shared_file_done && shared_fs_error!=0)$fatal(1,"shared stream error %h",shared_fs_error);
    if (u_streamer.state != prev_state)
      $display("[%0t] state %0d -> %0d owner=%0d rem=%0d lba=%0d",$time,prev_state,u_streamer.state,stream_owner,u_streamer.remaining_bytes,u_streamer.sector_lba);
    prev_state <= u_streamer.state;
  end

  // ===== 字节计数 =====
  integer cover_bytes=0, lyric_bytes=0, wav_bytes=0;
  integer cover_dones=0, lyric_dones=0, wav_dones=0;
  always @(posedge clk) begin
    if (streamer_byte_valid) cover_bytes=cover_bytes+1;
    if (lyric_file_valid)    lyric_bytes=lyric_bytes+1;
    if (wav_file_valid)      wav_bytes=wav_bytes+1;
    if (shared_file_done) $display("[%0t] shared done owner=%0d bytes(c/l/w)=%0d/%0d/%0d err=%02h",$time,stream_owner,cover_bytes,lyric_bytes,wav_bytes,shared_fs_error);
    if (streamer_file_done)  begin cover_dones=cover_dones+1; $display("[%0t] COVER DONE",$time); end
    if (lyric_file_done)     begin lyric_dones=lyric_dones+1; $display("[%0t] LYRIC DONE",$time); end
    if (wav_file_done)       begin wav_dones=wav_dones+1; $display("[%0t] WAV DONE",$time); end
  end

  task start_cover(input [31:0] cl, input [31:0] sz);
    begin
      @(negedge clk); load_cluster=cl; load_file_size=sz; load_start=1;
      @(negedge clk); load_start=0;
    end
  endtask
  task start_lyric(input [31:0] cl, input [31:0] sz);
    begin
      lyric_sector_mode=1;              // owner切到1（当拍复位流读器）
      @(negedge clk);                   // 等owner_switch拍过去
      lyric_first_cluster=cl; lyric_file_size=sz; lyric_file_start=1;
      @(negedge clk); lyric_file_start=0;
    end
  endtask
  task start_wav(input [31:0] cl, input [31:0] sz, input [31:0] off);
    begin
      wav_first_cluster=cl; wav_file_size=sz; wav_start_offset=off;
      wav_play_en=1; wav_file_start=1;  // owner=2，释放复位
      @(negedge clk); wav_file_start=0;
    end
  endtask

  initial begin
    repeat(8) @(negedge clk); rst=0;
    repeat(4) @(negedge clk);
    // ---- 阶段A：封面两张（owner 0） ----
    start_cover(10,3000);
    wait(streamer_file_done); @(posedge clk); #1;
    if (cover_bytes!=3000) $fatal(1,"cover0 bytes %0d != 3000",cover_bytes);
    start_cover(12,3000);
    wait(streamer_file_done); @(posedge clk); #1;
    if (cover_bytes!=6000) $fatal(1,"cover1 bytes %0d != 6000",cover_bytes);
    if (cover_dones!=2) $fatal(1,"cover dones %0d != 2",cover_dones);
    // ---- 阶段B：sd_free 上升，owner 0->2，WAV未播放时流读器保持复位 ----
    sd_free=1;
    repeat(4) @(negedge clk);
    // ---- 阶段C：歌词加载两次文件（owner 1，字体+歌词） ----
    start_lyric(20,500);
    wait(lyric_file_done); @(posedge clk); #1;
    if (lyric_bytes!=500) $fatal(1,"font bytes %0d != 500",lyric_bytes);
    lyric_sector_mode=0;                // 模拟M_TRACK间隙（owner短暂回2，wav_play_en=0仍复位）
    repeat(2) @(negedge clk);
    start_lyric(22,200);
    wait(lyric_file_done); @(posedge clk); #1;
    if (lyric_bytes!=700) $fatal(1,"lrc bytes %0d != 700",lyric_bytes);
    if (lyric_dones!=2) $fatal(1,"lyric dones %0d != 2",lyric_dones);
    // Bounded lyric/font read shares the same live offset mux as WAV seeks.
    lyric_start_offset=512;lyric_file_partial=1;
    start_lyric(20,1700);
    wait(lyric_file_done); @(posedge clk); #1;
    if(lyric_bytes!=1888 || lyric_dones!=3)$fatal(1,"lyric range owner/offset wrong");
    lyric_start_offset=0;lyric_file_partial=0;
    lyric_sector_mode=0;
    // ---- 阶段D：WAV流（owner 2，含背压） ----
    repeat(4) @(negedge clk);
    fork
      begin : wav_run
        start_wav(30,8000,0);
        wait(wav_file_done); @(posedge clk); #1;
      end
      begin : backpressure
        integer k;
        for (k=0;k<6;k=k+1) begin
          repeat(37) @(negedge clk);
          wav_can_read_sector=0;
          repeat(11) @(negedge clk);
          wav_can_read_sector=1;
        end
      end
    join
    if (wav_bytes!=8000) $fatal(1,"wav bytes %0d != 8000",wav_bytes);
    if (wav_dones!=1) $fatal(1,"wav dones %0d != 1",wav_dones);
    // ---- 阶段E：WAV停止 -> 歌词(owner 1) -> WAV重启（模拟切歌） ----
    wav_play_en=0;
    repeat(4) @(negedge clk);
    start_lyric(20,500);
    wait(lyric_file_done); @(posedge clk); #1;
    lyric_sector_mode=0;
    repeat(4) @(negedge clk);
    start_wav(30,8000,44);              // 带seek偏移重启
    wait(wav_file_done); @(posedge clk); #1;
    if (wav_bytes!=8000+7956) $fatal(1,"wav restart total bytes %0d != 15956",wav_bytes);
    if (wav_dones!=2) $fatal(1,"wav dones %0d != 2",wav_dones);
    $display("PASS shared streamer real payload/offset and zero fs_error, bounded lyric window, full-file covers/WAV and owner handoff: cover %0d/%0d, lyric %0d/%0d, wav %0d/%0d",
             cover_bytes,cover_dones,lyric_bytes,lyric_dones,wav_bytes,wav_dones);
    $finish;
  end
  initial begin #20000000; $fatal(1,"timeout: cover=%0d/%0d lyric=%0d/%0d wav=%0d/%0d owner=%0d",
      cover_bytes,cover_dones,lyric_bytes,lyric_dones,wav_bytes,wav_dones,stream_owner); end
endmodule
