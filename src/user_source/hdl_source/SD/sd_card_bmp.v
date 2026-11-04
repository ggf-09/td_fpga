
// =============================================================================
// 第8课：四bank帧缓存架构改造
//   本模块删除官方双缓冲管理（write_buf_idx/disp_buf_idx/pending_buf_idx、
//   write_req/write_en/write_data接口、写完成toggle同步），改为：
//     1) BMP字节流解析输出像素流 pixel_valid/pixel_rgb，帧末发 frame_commit；
//     2) 上电扫描完成后把 PIC1~4 加载到 bank0~3（load_start/image_index
//        驱动 media_frame_loader），加载完成标记 image_complete 由loader维护；
//        跨页重载按 requested_slot 从选中槽开始轮转（选中封面最先进SDRAM）；
//     3) 切换图片不再重新加载：按键脉冲输出给 media_player_control，
//        在帧消隐期提交 active_index 即完成零延迟切换；
//     4) 加载错误处理保留：流读错误重试1次、字节流停滞1秒强制中止（任意大小
//        高清图正常读取不超时），错误码沿用
//        A/b/C/d/E/F 数码管约定。
//   保留不变：SD卡底层驱动、FAT32卷扫描器、FAT32文件流读器、扇区仲裁、
//             BMP头解析（数据偏移量自适应）、按键消抖。
// =============================================================================
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    // === 第7课：升级为FAT32文件系统后按文件名匹配PIC1~4.BMP，以下物理扇区扫描参数保留兼容但不再使用 ===
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    // === 第2课参数保留兼容；第8课起轮播由media_player_control实现，控制器无“上一张”端口，长按不再使用 ===
    parameter integer LONG_PRESS_MS     = 1000,
    parameter integer AUTO_PLAY_MS      = 3000, MENU_SUPPORT=0
)(
    input                       clk,                // sd_card_clk 100MHz
    input                       rst,                // 高有效复位
    input wire checkpoint_snapshot_valid,
    input wire [3:0] checkpoint_snapshot_track,
    input wire [31:0] checkpoint_snapshot_frame,checkpoint_snapshot_size,checkpoint_snapshot_cluster,
    output wire checkpoint_boot_ready,checkpoint_restore_valid,
    output wire [3:0] checkpoint_restore_track,
    output wire [31:0] checkpoint_restore_frame,checkpoint_restore_size,checkpoint_restore_cluster,
    output wire checkpoint_enabled,checkpoint_error,
    input                       sdr_init_done,      // SDRAM初始化完成前禁止扫描
    input                       key_next,
    input                       key_auto,
    input                       page_start,
    input [1:0]                 requested_page,
    input [1:0]                 requested_slot,  // 跨页目标槽（router的cover_slot），选中封面优先加载
    output [1:0]                active_page,
    output [15:0]               library_playable,
    output                      page_done,
    output                      cache_invalidate,
    input  [15:0]               bmp_width,          // 保留端口兼容（FAT32版不做分辨率校验）
    input  [15:0]               bmp_height,         // 同上

    // === 第8课：像素流输出 → media_frame_loader（与clk同域，loader挂在sd_card_clk） ===
    output                      pixel_valid,        // 缩放后的640x480像素有效
    output [23:0]               pixel_rgb,          // 像素RGB（{R,G,B}）
    output reg                  frame_commit,       // 帧提交：源文件无错读完单拍脉冲
    output reg [7:0]            decode_error,       // 解码错误脉冲（流读错/超时中止时打出，非0）
    output [63:0]               meta_width_bcd,     // 四个bank的原始宽度BCD
    output [63:0]               meta_height_bcd,    // 四个bank的原始高度BCD
    output reg [3:0]            meta_valid,         // 仅在对应图片加载成功后置位

    // === 第8课：加载控制 ↔ media_frame_loader ===
    output reg                  menu_ready,load_menu,
    output reg                  load_start,         // 启动加载单拍脉冲（同时驱动流读器与loader）
    output reg [1:0]            load_image_index,   // 目标图片/bank编号（0~3）
    input                       loader_load_done,   // loader加载完成脉冲
    input  [7:0]                loader_memory_error,// loader错误码（0=成功）
    input  [3:0]                image_complete,     // 4张图片加载完成标记（loader维护）

    // === 第8课：按键脉冲 → media_player_control（已含消抖；扫描完成且有图才放行） ===
    output                      key_next_press,     // KEY1短按：下一张
    output                      key_auto_press,     // KEY2短按：自动轮播开/关

    // === 调试：扫描/加载错误码（A=SD读扇区错误 b=引导签名错 C=BPB不支持 d=未找到PIC E=重试耗尽 F=加载超时） ===
    output reg [3:0]            err_code,

    // === 第11课：WAV流播放器SD扇区接口（第三客户端，SEQ_DONE后独占SD卡） ===
    output                      sd_free,             // 首轮图片加载全部结束（seq_state==SEQ_DONE），SD卡空闲
    output [3:0]                song_valid,
    output [31:0]               song0_cluster,
    output [31:0]               song1_cluster,
    output [31:0]               song2_cluster,
    output [31:0]               song3_cluster,
    output [31:0]               song0_size,
    output [31:0]               song1_size,
    output [31:0]               song2_size,
    output [31:0]               song3_size,
    output [3:0]                lrc_valid,
    output [31:0]               lrc0_cluster,
    output [31:0]               lrc1_cluster,
    output [31:0]               lrc2_cluster,
    output [31:0]               lrc3_cluster,
    output [31:0]               lrc0_size,
    output [31:0]               lrc1_size,
    output [31:0]               lrc2_size,
    output [31:0]               lrc3_size,
    output                      font_valid,
    output [31:0]               font_cluster,
    output [31:0]               font_size,
    output [7:0]                media_sectors_per_cluster,
    output [31:0]               media_fat_start_lba,
    output [31:0]               media_data_start_lba,
    output [31:0]               media_max_cluster,
    // === 共享流读器文件级接口（三客户端复用同一个FAT链遍历器，见u_streamer注释） ===
    // owner：扫描/封面加载阶段=封面（内部），sd_free后 lyric_sector_mode=1 为歌词，否则为WAV
    output                      wav_sector_busy,        // 控制FSM用：SD忙（未空闲/歌词占用/适配器忙）
    input                       wav_play_en,            // WAV客户端复位项（=0时共享流读器保持复位）
    input                       wav_can_read_sector,    // WAV FIFO扇区级背压
    input                       wav_file_start,
    input  [31:0]               wav_first_cluster,
    input  [31:0]               wav_file_size,
    input  [31:0]               wav_start_offset,       // 快进/后退起始偏移（封面/歌词恒0）
    output                      wav_file_busy,
    output                      wav_file_done,
    output                      wav_file_valid,
    output [7:0]                wav_file_byte,
    output [31:0]               wav_file_offset,
    output [7:0]                wav_file_error,
    input                       lyric_sector_mode,
    input                       lyric_file_start,
    input  [31:0]               lyric_first_cluster,
    input  [31:0]               lyric_file_size,
    input  [31:0]               lyric_start_offset,
    input                       lyric_file_partial,
    output                      lyric_file_done,
    output                      lyric_file_valid,
    output [7:0]                lyric_file_byte,
    output [31:0]               lyric_file_offset,
    output [7:0]                lyric_file_error,

    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

// 一帧像素数（640x480），第8课：用于像素流截断保护与loader的IMAGE_WORDS一致
localparam [31:0] IMAGE_WORDS = 32'd307200;

wire key_next_press_raw;
wire key_auto_press_raw;
wire key_auto_stable;   // KEY2消抖后的稳定状态（第8课控制器无上一张端口，长按不再使用，保留测量）

// Typed scanner and arbitration nets precede checkpoint assignments/ports.
wire             scanner_scan_done;
wire [7:0]       scanner_spc;
wire [31:0]      scanner_data_start;
wire [31:0]      scanner_max_cluster;
reg              arb_sector_req;
reg  [31:0]      arb_sector_lba;
wire             arb_sector_busy;
wire             arb_sector_valid;
wire [7:0]       arb_sector_byte;
wire [8:0]       arb_sector_byte_index;
wire             arb_sector_done;
wire [7:0]       arb_sector_error;

wire [1:0] checkpoint_slots;
wire [31:0] checkpoint_cluster_a,checkpoint_cluster_b;
wire ck_want,ck_read_req,ck_write_req,ck_write_next,ck_write_done,ck_write_error;
wire [31:0] ck_read_lba,ck_write_lba;
wire [7:0] ck_write_byte;
reg ck_owner;
wire adapter_busy,adapter_valid,adapter_done;
wire [7:0] adapter_byte,adapter_error;
wire [8:0] adapter_index;
always @(posedge clk or posedge rst)begin
 if(rst)ck_owner<=0;
 else if(ck_owner)begin if(!ck_want && !adapter_busy)ck_owner<=0;end
 else if(ck_want && !adapter_busy && !arb_sector_req)ck_owner<=1;
end
assign arb_sector_busy=adapter_busy || ck_owner || ck_want;
assign arb_sector_valid=adapter_valid && !ck_owner;
assign arb_sector_done=adapter_done && !ck_owner;
assign arb_sector_byte=adapter_byte;
assign arb_sector_byte_index=adapter_index;
assign arb_sector_error=adapter_error;
playback_checkpoint #(.SAVE_FRAME_SHIFT(17)) u_checkpoint(
 .clk(clk),.rst_n(~rst),.catalog_done(scanner_scan_done),.slots_valid(checkpoint_slots),
 .cluster_a(checkpoint_cluster_a),.cluster_b(checkpoint_cluster_b),
 .data_start(scanner_data_start),.max_cluster(scanner_max_cluster),.spc(scanner_spc),
 .snapshot_valid(checkpoint_snapshot_valid),.snapshot_track(checkpoint_snapshot_track),
 .snapshot_frame(checkpoint_snapshot_frame),.snapshot_size(checkpoint_snapshot_size),
 .snapshot_cluster(checkpoint_snapshot_cluster),
 .boot_ready(checkpoint_boot_ready),.restore_valid(checkpoint_restore_valid),
 .restore_track(checkpoint_restore_track),.restore_frame(checkpoint_restore_frame),
 .restore_size(checkpoint_restore_size),.restore_cluster(checkpoint_restore_cluster),
 .enabled(checkpoint_enabled),.save_error(checkpoint_error),.want_bus(ck_want),.bus_granted(ck_owner),
 .read_req(ck_read_req),.read_lba(ck_read_lba),.read_valid(adapter_valid && ck_owner),
 .read_byte(adapter_byte),.read_index(adapter_index),.read_done(adapter_done && ck_owner),.read_error(adapter_error),
 .write_req(ck_write_req),.write_lba(ck_write_lba),.write_byte(ck_write_byte),
 .write_next(ck_write_next),.write_done(ck_write_done),.write_error(ck_write_error)
);
// 官方SD卡底层驱动（sd_card_top）接口
wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             sd_sec_read_error;   //读扇区重试耗尽后的失败标志（与read_end同拍）
wire             sd_init_done;

// === FAT32卷扫描器输出 ===
wire             scanner_scan_busy;

wire [7:0]       scanner_fs_error;

wire [31:0]      scanner_fat_start;


wire [15:0] library_bmp_valid,library_song_valid;
wire [1:0] scanner_loaded_page,catalog_page;
wire catalog_page_start,page_reloading,page_quiescing;
assign library_playable=library_bmp_valid & library_song_valid;

wire [3:0]       scan_resource_valid;
wire [31:0]      scanner_r0_cluster;
wire [31:0]      scanner_r1_cluster;
wire [31:0]      scanner_r2_cluster;
wire [31:0]      scanner_r3_cluster;
wire [31:0]      scanner_r0_size;
wire [31:0]      scanner_r1_size;
wire [31:0]      scanner_r2_size;
wire [31:0]      scanner_r3_size;

assign media_sectors_per_cluster = scanner_spc;
assign media_fat_start_lba = scanner_fat_start;
assign media_data_start_lba = scanner_data_start;
assign media_max_cluster = scanner_max_cluster;

// === 文件流读取器输出 ===
wire             streamer_file_busy;
wire             streamer_file_done;
wire             streamer_byte_valid;
wire [7:0]       streamer_byte;
wire [7:0]       streamer_fs_error;

wire [18:0]      decoder_out_count;
wire             decoder_scale_complete;
wire             decoder_header_error;
wire [15:0]      decoder_width_bcd;
wire [15:0]      decoder_height_bcd;
wire             decoder_dims_valid;

// 扇区读仲裁：扫描阶段用扫描器，加载阶段用流读器（二者不会同时进行，分时复用SD卡）
reg              use_streamer;
reg              scan_done_latched;   // 官方bmp_read的scan_done是电平，FAT32扫描器是单拍脉冲，需锁存

wire             scanner_sector_req;
wire [31:0]      scanner_sector_lba;
wire             scanner_sector_busy;
wire             scanner_sector_valid;
wire [7:0]       scanner_sector_byte;
wire [8:0]       scanner_sector_byte_index;
wire             scanner_sector_done;
wire [7:0]       scanner_sector_error;

wire             streamer_sector_req;
wire [31:0]      streamer_sector_lba;










reg              scan_start_pulse;
reg              scan_kicked;
reg  [3:0]       scan_valid_latched;   // 第8课：锁存resource_valid，顺序加载时跳过缺失文件
reg  [2:0]       img_found_count;
reg  [31:0]      img_cluster0;         // FAT32：起始簇号+文件大小
reg  [31:0]      img_cluster1;
reg  [31:0]      img_cluster2;
reg  [31:0]      img_cluster3;
reg  [31:0]      img_size0;
reg  [31:0]      img_size1;
reg  [31:0]      img_size2;
reg  [31:0]      img_size3;

// === 第8课：顺序加载状态机 ===
localparam [1:0] SEQ_IDLE = 2'd0;   // 等扫描完成
localparam [1:0] SEQ_KICK = 2'd1;   // 发起当前图片加载（或跳过缺失文件）
localparam [1:0] SEQ_WAIT = 2'd2;   // 等loader_load_done
localparam [1:0] SEQ_DONE = 2'd3;   // 首轮4张加载结束
reg  [1:0]       seq_state;
wire scanner_menu_valid;
wire [31:0] scanner_menu_cluster,scanner_menu_size;
reg menu_attempted;
reg  [2:0]       seq_idx;           // 当前加载步骤0~3（槽号=步骤+priority_slot轮转），4=MENU，5=全部处理完
// 选中封面优先：跨页加载从目标槽开始按mod4轮转（如选中槽2则顺序2,3,0,1），
// 让router等待的那张封面最先进SDRAM，其余3张后台补齐；上电首轮requested_slot=0即原顺序。
reg  [1:0]       priority_slot;
wire [1:0]       seq_slot = seq_idx[1:0] + priority_slot;
cover_page_controller u_cover_pages(
 .clk(clk),.rst_n(~rst),.init_ready(sd_init_done),
 .reload_request(page_start),.requested_page(requested_page),
 .sector_busy(arb_sector_busy),.cache_done(seq_state==SEQ_DONE),
 .metadata_done(scanner_scan_done),.metadata_page(scanner_loaded_page),
 .reloading(page_reloading),.quiescing(page_quiescing),.cache_invalidate(cache_invalidate),
 .catalog_start(catalog_page_start),.catalog_page(catalog_page),.active_page(active_page),.page_done(page_done)
);







reg              load_busy;
reg  [26:0]      load_timeout_cnt; // 0..100000001; abort before 27-bit wrap
reg              load_abort;        // 加载错误强制中止单拍（复位流读器用）
reg              timeout_abort;     // 本次加载因超时被中止（load_done到来时不再重试，直接记F跳到下一张）
reg              format_abort;      // BMP格式不支持，记2后直接跳下一张
reg              source_done_q;     // file_done后延迟一拍检查缩放输出总数
localparam [1:0] MAX_RETRIES = 2'd1; // 流读/解码错误最多重试1次，失败跳过该图（保留上一张内容）
reg  [1:0]       retry_count;
reg  [31:0]      load_cluster;
reg  [31:0]      load_file_size;
// 停滞超时阈值：字节持续到达时永不超时；SD流完全停滞超过1秒(@100MHz)才判定卡死。
localparam [31:0] LOAD_STALL_LIMIT = CLK_FREQ_HZ;
reg load_timeout_expired;
// WATCHDOG_FLAG_BEGIN
// Register the terminal decision one count early. This retains the original
// > LIMIT abort cycle while removing the wide comparator from counter feedback.
always @(posedge clk or posedge rst)begin
 if(rst)load_timeout_expired<=0;
 else load_timeout_expired<=load_busy && !streamer_byte_valid && load_timeout_cnt==LOAD_STALL_LIMIT;
end
// WATCHDOG_FLAG_END

reg [15:0] meta_w0,meta_w1,meta_w2,meta_w3;
reg [15:0] meta_h0,meta_h1,meta_h2,meta_h3;
assign meta_width_bcd  = {meta_w3,meta_w2,meta_w1,meta_w0};
assign meta_height_bcd = {meta_h3,meta_h2,meta_h1,meta_h0};

// 第8课：按键脉冲输出门控——扫描完成且有图才放行（自动轮播要求至少2张图）
assign key_next_press = key_next_press_raw && scan_done_latched && (img_found_count > 3'd0);
assign key_auto_press = key_auto_press_raw && scan_done_latched && (img_found_count > 3'd1);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (50)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press_raw),
    .button_stable_out()            // KEY1只有短按功能，无需稳定状态
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (50)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press_raw),
    .button_stable_out(key_auto_stable)
);

// === cluster_lut/size_lut（地址从物理扇区号变为起始簇号+文件大小）===
function [31:0] cluster_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: cluster_lut = img_cluster0;
            2'd1: cluster_lut = img_cluster1;
            2'd2: cluster_lut = img_cluster2;
            2'd3: cluster_lut = img_cluster3;
            default: cluster_lut = img_cluster0;
        endcase
    end
endfunction

function [31:0] size_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: size_lut = img_size0;
            2'd1: size_lut = img_size1;
            2'd2: size_lut = img_size2;
            2'd3: size_lut = img_size3;
            default: size_lut = img_size0;
        endcase
    end
endfunction

// === 扫描结果锁存 + SD卡仲裁切换 ===
// 官方bmp_read的scan_done是电平（扫完一直为高），FAT32扫描器是单拍脉冲，这里锁存成电平
// 同时把4个文件的簇号/大小缓存下来，img_found_count由resource_valid统计
always @(posedge clk or posedge rst) begin
    if (rst) begin
        scan_done_latched  <= 1'b0;
        use_streamer       <= 1'b0;
        scan_valid_latched <= 4'd0;
        img_found_count    <= 3'd0;
        img_cluster0       <= 32'd0;
        img_cluster1       <= 32'd0;
        img_cluster2       <= 32'd0;
        img_cluster3       <= 32'd0;
        img_size0          <= 32'd0;
        img_size1          <= 32'd0;
        img_size2          <= 32'd0;
        img_size3          <= 32'd0;
    end else if (!sd_init_done) begin
        scan_done_latched  <= 1'b0;
        use_streamer       <= 1'b0;
        scan_valid_latched <= 4'd0;
        img_found_count    <= 3'd0;
        img_cluster0       <= 32'd0;
        img_cluster1       <= 32'd0;
        img_cluster2       <= 32'd0;
        img_cluster3       <= 32'd0;
        img_size0          <= 32'd0;
        img_size1          <= 32'd0;
        img_size2          <= 32'd0;
        img_size3          <= 32'd0;
    end else if (scan_start_pulse || cache_invalidate) begin
        scan_done_latched  <= 1'b0;
        use_streamer       <= 1'b0;
        scan_valid_latched <= 4'd0;
        img_found_count    <= 3'd0;
    end else if (scanner_scan_done) begin
        scan_done_latched  <= 1'b1;
        // 至少找到1个文件才切换到流读器，避免流读器拿到无效的文件系统参数
        use_streamer       <= (scan_resource_valid != 4'd0);
        scan_valid_latched <= scan_resource_valid;
        img_found_count    <= {2'b0, scan_resource_valid[3]} + {2'b0, scan_resource_valid[2]} +
                              {2'b0, scan_resource_valid[1]} + {2'b0, scan_resource_valid[0]};
        img_cluster0       <= scanner_r0_cluster;
        img_cluster1       <= scanner_r1_cluster;
        img_cluster2       <= scanner_r2_cluster;
        img_cluster3       <= scanner_r3_cluster;
        img_size0          <= scanner_r0_size;
        img_size1          <= scanner_r1_size;
        img_size2          <= scanner_r2_size;
        img_size3          <= scanner_r3_size;
    end
end

// === 上电后自动发起一次FAT32卷扫描（须等SDRAM初始化完成）===
always @(posedge clk or posedge rst) begin
    if (rst) begin
        scan_start_pulse <= 1'b0;
        scan_kicked      <= 1'b0;
    end else if (!sd_init_done) begin
        scan_start_pulse <= 1'b0;
        scan_kicked      <= 1'b0;
    end else if (!scan_kicked && sdr_init_done) begin
        scan_start_pulse <= 1'b1;
        scan_kicked      <= 1'b1;
    end else begin
        scan_start_pulse <= 1'b0;
    end
end

// === 第8课：顺序加载状态机（上电扫描完成后把PIC1~4依次加载到bank0~3）===
// 每张图片：load_start单拍同时启动流读器与loader；像素流经loader的FIFO+burst写进对应bank；
// loader_load_done回收结果：成功→下一张；解码/流读错误→重试1次后跳过（记E）；超时→中止后跳过（记F）。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        seq_state        <= SEQ_IDLE;
        seq_idx          <= 3'd0;
        priority_slot    <= 2'd0;
        load_start       <= 1'b0;
        load_image_index <= 2'd0;
        menu_ready<=0;load_menu<=0;menu_attempted<=0;
        load_cluster     <= 32'd0;
        load_file_size   <= 32'd0;
        load_busy        <= 1'b0;
        load_timeout_cnt <= 32'd0;
        load_abort       <= 1'b0;
        timeout_abort    <= 1'b0;
        format_abort     <= 1'b0;
        source_done_q    <= 1'b0;
        retry_count      <= 2'd0;
        err_code         <= 4'd0;
        frame_commit     <= 1'b0;
        decode_error     <= 8'd0;
        meta_valid       <= 4'd0;
        meta_w0<=0;meta_w1<=0;meta_w2<=0;meta_w3<=0;
        meta_h0<=0;meta_h1<=0;meta_h2<=0;meta_h3<=0;
    end else begin
        load_start   <= 1'b0;
        frame_commit <= 1'b0;
        decode_error <= 8'd0;
        load_abort   <= 1'b0;
        if (load_start)
            source_done_q <= 1'b0;

        // 锁存扫描错误码（A=扇区错误 b=引导签名 C=BPF不支持 d=未找到PIC）
        if (scanner_scan_done && (scanner_fs_error != 8'h00)) begin
            case (scanner_fs_error)
                8'h10:   err_code <= 4'hA;
                8'h20:   err_code <= 4'hb;
                8'h21:   err_code <= 4'hC;
                default: err_code <= 4'hd;
            endcase
        end

        if(!sd_init_done)begin menu_ready<=0;menu_attempted<=0;end
        if (!sd_init_done || cache_invalidate) begin
            load_menu<=0;
            seq_state        <= SEQ_IDLE;
            seq_idx          <= 3'd0;
            load_start       <= 1'b0;
            load_busy        <= 1'b0;
            load_timeout_cnt <= 32'd0;
            timeout_abort    <= 1'b0;
            format_abort     <= 1'b0;
            source_done_q    <= 1'b0;
            retry_count      <= 2'd0;
            err_code         <= 4'd0;
            frame_commit     <= 1'b0;
            decode_error     <= 8'd0;
            meta_valid       <= 4'd0;
        end else begin
            // file_done后延迟一拍再提交，避开末像素计数同拍更新竞态。
            if (load_busy && streamer_file_done && (streamer_fs_error == 8'd0))
                source_done_q <= 1'b1;
            if (load_busy && source_done_q) begin
                source_done_q <= 1'b0;
                if (decoder_scale_complete)
                    frame_commit <= 1'b1;
                else
                    decode_error <= 8'h44;
            end

            // 流读错误（FAT链断/簇越界/提前EOF等）：立即让loader报ERR_DECODE退出。
            if (load_busy && streamer_file_done && (streamer_fs_error != 8'd0)) begin
                source_done_q <= 1'b0;
                decode_error  <= 8'h44;
            end

            // 不支持的BMP格式无需读完整个文件，安全收回SD并跳到下一图。
            if (load_busy && decoder_header_error) begin
                load_abort       <= 1'b1;
                decode_error     <= 8'h44;
                format_abort     <= 1'b1;
                source_done_q    <= 1'b0;
                load_timeout_cnt <= 32'd0;
            end

            // 停滞超时：字节持续到达就说明大高清图仍在正常读取，永不超时；
            // 只有SD流完全停滞超过1秒（卡死/FAT链异常）才强制中止收回SD卡。
            // WATCHDOG_COUNTER_BEGIN
            if (load_busy) begin
                if (streamer_byte_valid) begin
                    load_timeout_cnt <= 32'd0;
                end else if (load_timeout_expired) begin
                    load_abort       <= 1'b1;   // 强制复位流读器，收回SD卡控制权
                    decode_error     <= 8'h44;
                    timeout_abort    <= 1'b1;
                    source_done_q    <= 1'b0;
                    load_timeout_cnt <= 32'd0;
                end else begin
                    load_timeout_cnt <= load_timeout_cnt + 32'd1;
                end
            end else begin
                load_timeout_cnt <= 32'd0;
            end

            // WATCHDOG_COUNTER_END
            case (seq_state)
                SEQ_IDLE: begin
                    if (scan_done_latched) begin
                        seq_state   <= img_found_count!=0 || (MENU_SUPPORT!=0 && scanner_menu_valid && !menu_attempted) ? SEQ_KICK : SEQ_DONE;
                        seq_idx     <= 3'd0;
                        retry_count <= 2'd0;
                        priority_slot <= requested_slot;   // 本次页加载的起始槽（上电=0，跨页=选中槽）
                    end
                end
                SEQ_KICK: begin
                    if (seq_idx >= 3'd5) begin
                        seq_state <= SEQ_DONE;              // 4张全部处理完
                    end else if(seq_idx==4)begin
                        if(MENU_SUPPORT!=0 && scanner_menu_valid && (!menu_attempted || retry_count!=0))begin
                            load_menu<=1;menu_attempted<=1;load_start<=1;load_image_index<=0;
                            load_cluster<=scanner_menu_cluster;load_file_size<=scanner_menu_size;
                            load_busy<=1;timeout_abort<=0;format_abort<=0;source_done_q<=0;seq_state<=SEQ_WAIT;
                        end else seq_state<=SEQ_DONE;
                    end else if (!scan_valid_latched[seq_slot]) begin
                        seq_idx <= seq_idx + 3'd1;          // 跳过缺失文件
                    end else begin
                        load_menu<=0;
                        load_start       <= 1'b1;
                        load_image_index <= seq_slot;
                        load_cluster     <= cluster_lut(seq_slot);
                        load_file_size   <= size_lut(seq_slot);
                        load_busy        <= 1'b1;
                        timeout_abort    <= 1'b0;
                        format_abort     <= 1'b0;
                        source_done_q    <= 1'b0;
                        meta_valid[seq_slot] <= 1'b0;
                        seq_state        <= SEQ_WAIT;
                    end
                end
                SEQ_WAIT: begin
                    if (loader_load_done) begin
                        load_busy <= 1'b0;
                        if (timeout_abort) begin
                            // 超时不重试，记F后直接下一张
                            err_code      <= 4'hF;
                            timeout_abort <= 1'b0;
                            retry_count   <= 2'd0;
                            seq_idx       <= seq_idx + 3'd1;
                            seq_state     <= SEQ_KICK;
                        end else if (format_abort) begin
                            // 不支持的BMP格式：重试无意义，记2后跳过。
                            err_code      <= 4'h2;
                            format_abort  <= 1'b0;
                            retry_count   <= 2'd0;
                            seq_idx       <= seq_idx + 3'd1;
                            seq_state     <= SEQ_KICK;
                        end else if (loader_memory_error == 8'd0) begin
                            if(load_menu)menu_ready<=1;
                            if(!load_menu) begin
                                meta_valid[load_image_index] <= decoder_dims_valid;
                                case(load_image_index)
                                    0: begin meta_w0<=decoder_width_bcd;meta_h0<=decoder_height_bcd;end
                                    1: begin meta_w1<=decoder_width_bcd;meta_h1<=decoder_height_bcd;end
                                    2: begin meta_w2<=decoder_width_bcd;meta_h2<=decoder_height_bcd;end
                                    default: begin meta_w3<=decoder_width_bcd;meta_h3<=decoder_height_bcd;end
                                endcase
                            end
                            // 加载成功
                            err_code    <= 4'd0;
                            retry_count <= 2'd0;
                            seq_idx     <= seq_idx + 3'd1;
                            seq_state   <= SEQ_KICK;
                        end else if (retry_count < MAX_RETRIES) begin
                            // 解码/流读错误重试同一张图（cluster/size/idx仍锁存，直接复用）
                            retry_count <= retry_count + 2'd1;
                            seq_state   <= SEQ_KICK;
                        end else begin
                            // 重试耗尽：跳过该图（image_complete不置位，控制器不会切到该bank）
                            err_code    <= 4'hE;
                            retry_count <= 2'd0;
                            seq_idx     <= seq_idx + 3'd1;
                            seq_state   <= SEQ_KICK;
                        end
                    end
                end
                SEQ_DONE: begin
                    // 首轮4张加载结束；卡拔出/重新初始化（!sd_init_done）会复位到SEQ_IDLE重新加载
                    seq_state <= SEQ_DONE;
                end
                default: seq_state <= SEQ_IDLE;
            endcase
        end
    end
end

//=== BMP头解析 + 头校验与流式最近邻缩放（640x480输出） ===
bmp_pic_decoder u_pic_decoder (
    .clk              (clk),
    .rst              (rst),
    .start            (load_start),
    .abort            (load_abort | cache_invalidate),
    .file_size        (load_file_size),
    .byte_valid       (streamer_byte_valid),
    .byte_in          (streamer_byte),
    .pixel_valid      (pixel_valid),
    .pixel_rgb        (pixel_rgb),
    .out_count        (decoder_out_count),
    .scale_complete   (decoder_scale_complete),
    .header_error     (decoder_header_error),
    .src_width_bcd    (decoder_width_bcd),
    .src_height_bcd   (decoder_height_bcd),
    .dims_valid       (decoder_dims_valid)
);

//=== 扇区读仲裁（扫描器/共享流读器两方分时复用SD卡，同一时刻只有一个在跑）===
// 共享流读器内部再按owner服务封面/歌词/WAV三客户端（见u_streamer注释）；
// 第11课：seq_state==SEQ_DONE（首轮图片加载结束）后SD卡永久空闲，WAV/歌词独占；
// SEQ_DONE只在卡拔出重初始化（!sd_init_done）时退出，那时整个SD子系统本就失效
assign sd_free = (seq_state == SEQ_DONE) && !page_reloading;

always @(*) begin
    if (page_quiescing) begin
        arb_sector_req = scanner_sector_req;
        arb_sector_lba = scanner_sector_lba;
    end else if (sd_free || use_streamer) begin
        arb_sector_req = streamer_sector_req;
        arb_sector_lba = streamer_sector_lba;
    end else begin
        arb_sector_req = scanner_sector_req;
        arb_sector_lba = scanner_sector_lba;
    end
end

// 返回信号广播给两个模块（空闲模块处于IDLE状态，不会误采样）
assign scanner_sector_busy       = arb_sector_busy;
assign scanner_sector_valid      = arb_sector_valid;
assign scanner_sector_byte       = arb_sector_byte;
assign scanner_sector_byte_index = arb_sector_byte_index;
assign scanner_sector_done       = arb_sector_done;
assign scanner_sector_error      = arb_sector_error;

// 控制FSM用的"SD忙"视图（语义与合并前一致：未空闲/歌词占用/适配器忙都算忙）
assign wav_sector_busy = !sd_free || lyric_sector_mode || arb_sector_busy;

// ---------- FAT32卷扫描器（识别文件系统+匹配PIC1~4.BMP目录项） ----------
fat32_library_scanner u_scanner (
    .checkpoint_valid(checkpoint_slots),.checkpoint_a_cluster(checkpoint_cluster_a),
    .checkpoint_b_cluster(checkpoint_cluster_b),
    .clk                 (clk),
    .rst_n               (~rst),            // 官方是高有效复位，FAT32模块是低有效
    .scan_start          (scan_start_pulse),
    .page_start          (catalog_page_start),
    .page_select         (catalog_page),
    .loaded_page         (scanner_loaded_page),
    .library_bmp_valid   (library_bmp_valid),
    .library_song_valid  (library_song_valid),
    .library_lrc_valid   (),
    .menu_valid(scanner_menu_valid),.menu_cluster(scanner_menu_cluster),.menu_size(scanner_menu_size),
    .scan_busy           (scanner_scan_busy),
    .scan_done           (scanner_scan_done),
    .fs_error            (scanner_fs_error),
    .partition_lba       (),
    .sectors_per_cluster (scanner_spc),
    .fat_start_lba       (scanner_fat_start),
    .data_start_lba      (scanner_data_start),
    .max_cluster         (scanner_max_cluster),
    .resource_valid      (scan_resource_valid),
    .resource0_cluster   (scanner_r0_cluster),
    .resource1_cluster   (scanner_r1_cluster),
    .resource2_cluster   (scanner_r2_cluster),
    .resource3_cluster   (scanner_r3_cluster),
    .resource0_size      (scanner_r0_size),
    .resource1_size      (scanner_r1_size),
    .resource2_size      (scanner_r2_size),
    .resource3_size      (scanner_r3_size),
    .song_valid          (song_valid),
    .song0_cluster       (song0_cluster),
    .song1_cluster       (song1_cluster),
    .song2_cluster       (song2_cluster),
    .song3_cluster       (song3_cluster),
    .song0_size          (song0_size),
    .song1_size          (song1_size),
    .song2_size          (song2_size),
    .song3_size          (song3_size),
    .lrc_valid           (lrc_valid),
    .lrc0_cluster        (lrc0_cluster),
    .lrc1_cluster        (lrc1_cluster),
    .lrc2_cluster        (lrc2_cluster),
    .lrc3_cluster        (lrc3_cluster),
    .lrc0_size           (lrc0_size),
    .lrc1_size           (lrc1_size),
    .lrc2_size           (lrc2_size),
    .lrc3_size           (lrc3_size),
    .font_valid          (font_valid),
    .font_cluster        (font_cluster),
    .font_size           (font_size),
    .sector_req          (scanner_sector_req),
    .sector_lba          (scanner_sector_lba),
    .sector_busy         (scanner_sector_busy),
    .sector_valid        (scanner_sector_valid),
    .sector_byte         (scanner_sector_byte),
    .sector_byte_index   (scanner_sector_byte_index),
    .sector_done         (scanner_sector_done),
    .sector_error        (scanner_sector_error)
);

// ---------- 共享FAT32文件流读取器（封面/歌词/WAV三客户端复用同一FAT链遍历器） ----------
// 三客户端时间上互斥：封面在 sd_free 之前加载；歌词在 WAV 停止后占用（lyric_sector_mode=1，
// 期间WAV保持复位）；WAV在 lyric_sector_mode=0 时流式播放。owner 切换当拍强制复位一周期，
// 清除上一客户端状态；各客户端复位语义与合并前三份独立实例完全一致：
//   封面=load_abort/cache_invalidate强制复位（加载超时收回SD卡控制权）；
//   歌词=sector_mode下降沿（经owner切换复位）；
//   WAV=wav_play_en=0期间保持复位。
// SEEK_SUPPORT=1 对封面/歌词以 start_offset=0 运行，与无SEEK版本逐拍等价。
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
    .sectors_per_cluster (scanner_spc),
    .fat_start_lba       (scanner_fat_start),
    .data_start_lba      (scanner_data_start),
    .max_cluster         (scanner_max_cluster),
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
assign streamer_file_busy  = stream_owner == 2'd0 && shared_file_busy;
assign streamer_file_done  = stream_owner == 2'd0 && shared_file_done;
assign streamer_byte_valid = stream_owner == 2'd0 && shared_file_valid;
assign streamer_byte       = shared_file_byte;
assign streamer_fs_error   = stream_owner == 2'd0 ? shared_fs_error : 8'd0;

assign wav_file_busy   = stream_owner == 2'd2 && shared_file_busy;
assign wav_file_done   = stream_owner == 2'd2 && shared_file_done;
assign wav_file_valid  = stream_owner == 2'd2 && shared_file_valid;
assign wav_file_byte   = shared_file_byte;
assign wav_file_offset = shared_file_offset;
assign wav_file_error  = stream_owner == 2'd2 ? shared_fs_error : 8'd0;

assign lyric_file_done   = stream_owner == 2'd1 && shared_file_done;
assign lyric_file_valid  = stream_owner == 2'd1 && shared_file_valid;
assign lyric_file_byte   = shared_file_byte;
assign lyric_file_offset = shared_file_offset;
assign lyric_file_error  = stream_owner == 2'd1 ? shared_fs_error : 8'd0;

// ---------- SD卡接口适配层（sector_*接口 → 官方sd_sec_*接口） ----------
sd_sector_adapter u_adapter (
    .clk                    (clk),
    .rst_n                  (~rst),
    // 新模块侧（接仲裁器输出）
    .sector_req             (ck_owner ? ck_read_req : arb_sector_req),
    .sector_lba             (ck_owner ? ck_read_lba : arb_sector_lba),
    .sector_busy            (adapter_busy),
    .sector_valid           (adapter_valid),
    .sector_byte            (adapter_byte),
    .sector_byte_index      (adapter_index),
    .sector_done            (adapter_done),
    .sector_error           (adapter_error),
    // 官方sd_card_top侧
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_read_error      (sd_sec_read_error)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_read_error      (sd_sec_read_error),
    .sd_sec_write           (ck_write_req && ck_owner),
    .sd_sec_write_addr      (ck_write_lba),
    .sd_sec_write_data      (ck_write_byte),
    .sd_sec_write_data_req  (ck_write_next),
    .sd_sec_write_error     (ck_write_error),
    .sd_sec_write_end       (ck_write_done)
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    // 消抖后的稳定状态输出（用于长按检测）
    output reg  button_stable_out
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
localparam integer DEBOUNCE_BITS=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES+1):1;
reg [DEBOUNCE_BITS-1:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0      <= 1'b1;
        button_sync1      <= 1'b1;
        button_stable     <= 1'b1;
        button_stable_out <= 1'b1;
        cnt               <= 32'd0;
        press_pulse       <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable     <= button_sync1;
                button_stable_out <= button_sync1;
                cnt               <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
