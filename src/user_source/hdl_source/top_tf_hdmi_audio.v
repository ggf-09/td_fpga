
// =============================================================================
// 第15课：缩略图交互选择
//   新增：thumbnail_controller（课件骨架+参考答案补全，sd_card_clk域）；
//         media_player_control 加 select_event/select_index 快速选择通道
//   交互（缩略图模式内）：KEY1短按松开=焦点右移（wrap）、KEY1按住≥1.2s松开=
//         确认选择（全屏显示焦点图）、KEY2单击=焦点左移、KEY2双击=退出不选；
//         KEY2双击（全屏）=进入缩略图。焦点跨域+帧边界锁存（黄框不撕裂）
//   转场：模式切换/确认都触发一次淡出淡入（transition_req→u_fade_transition），
//         期望模式ctrl_view_mode与select都在全黑时刻才应用（黑屏盖住坐标切换）；
//         全屏KEY1下一张语义不变（缩略图下KEY1被接管为导航，转场触发源处门控）
// =============================================================================
// 第14课：亮度/对比度调节 + 参数OSD
//   新增：brightness_contrast_adjust（课件骨架+参考答案补全，纯组合适配：
//         亮度coeff=255?256:b 逐位无损基准；对比度(x-128)*c>>>7+128算术右移饱和）
//         param_osd_overlay（第二状态行"B255 C128"，不动第9课OSD文件）
//   位置：transition_rgb → 亮度对比度 → OSD → 参数行 → 频谱 → adapter
//   参数：KEY2 按住1.2~3秒松开=亮度5档循环（255/192/128/64/32）；
//         按住≥3秒松开=对比度5档循环（128/160/192/255/64）；课件param_menu式
//         松开沿判定，帧边界锁存生效不跳变；长按误触的自动翻转松开时翻回
//   【第13讲按键调整】缩略图切换改KEY2双击（≤0.5s两次短按，自动轮播翻两次
//         净效果不变），原1.2s长按让位给参数调节（按键只有key1/key2可用，
//         key1短按=下一张不可撤销，故所有新交互都放key2）
// =============================================================================
// 第13课：图片缩放与缩略图
//   新增：thumbnail_layout（课件原样组合映射，供thumb_de/focus_border）；
//         media_frame_reader 内部生成缩略图地址序列（顺序流架构适配，见模块头注释）
//   布局：屏幕左上320x240四宫格（每格160x120=源图4:1最近邻），其余区域黑；
//         焦点格2px黄框（focus=当前播放图），未加载bank显示黑
//   模式切换：KEY2长按≥1.2s翻转（帧边界生效不撕裂）；长按会先触发一次自动轮播
//         翻转，检测到长按时再翻转回去（净效果=自动状态不变，仅切模式）
//   bilinear_8q8.v 为选做（完赛工程未实现），本工程不加入
// =============================================================================
// 第12课：音频可视化（柱形频谱）
//   现用：promax_audio_spectrum（64段胶囊柱彩虹频谱，Goertzel 120Hz~16.8kHz，中线对称生长）
//   备用：promax_audio_waveform（课件原版波形+峰值条，已注册未实例化，可回退）
//   插入位置：OSD叠加之后、rgb_video_adapter之前；de/vsync接未门控raw_de/raw_vs
//   抽取点：增益后样本wav_sample_gained+sample_valid（video_clk域，淡出随音量变矮）
//   使能：wav_active_pix2（WAV流播放中才显示，琶音期间不显示）
// =============================================================================
// 第11课：WAV音频播放
//   新增：wav_stream_player（BRAM循环缓冲+格雷码跨域+下溢静音）、audio_source_mux、sync_fade_gain
//   SD共享：wav播放器作为sd_card_bmp扇区仲裁第三客户端，SEQ_DONE（首轮图加载完）后独占SD卡
//   音频链：{WAV流(增益) / 琶音} → audio_source_mux → m06_pcm_contract_adapter → HDMI（不变）
//   音画同步：sync_fade_gain把第10课fade_alpha转为音量包络，两音源都跟随画面淡入淡出
//   PCM文件：固定LBA参数（WAV_START_LBA/WAV_TOTAL_SECTORS），PC工具转码后dd写入对应扇区
// =============================================================================
// 第10课：图片转场特效
//   新增：video_fade_transition（4状态机IDLE/OUT/HOLD/IN + 三组toggle+2FF跨域）
//   控制链路：bmp_key_next_press → 转场控制器 → （全黑时刻） → u_control.next_event
//   像素链路：selected_rgb → alpha乘法 → Wipe选择 → OSD（插在OSD之前）
//   手动"下一张"：淡出→全黑放行切换→淡入；自动轮播：index_commit后左→右Wipe揭示新图
// =============================================================================
// 第9课：OSD字幕叠加
//   新增：osd_overlay_24 + status_osd_overlay（4字符状态条：图片编号/自动A手动E/错误码hex）
//   插入点：selected_rgb像素mux之后、rgb_video_adapter之前（纯组合逻辑，零流水线延迟）
//   状态源：active_index_pix（本域直取）；auto_enabled/media_err（sd_card_clk域2FF同步）
//   帧边界锁存：OSD内部frame_start锁存状态，一帧内不变，不撕裂
// =============================================================================
// 第8课：四bank帧缓存架构（loader/reader分离）
//   删除：frame_read_write（读写耦合桥接）、video_timing_data、video_delay 三个实例
//   新增：media_frame_loader（帧加载器，sd_card_clk域，FIFO+burst写）
//         media_sdram_write_cdc（写命令跨域 100M→125M，128字块回放，写优先互斥）
//         media_frame_reader（帧读取器，mem_clk域burst读 + pix_clk域异步FIFO+prefetch）
//         media_player_control（播放控制，帧消隐期提交active_index，切换零延迟不撕裂）
//         video_timing_ctrl / rgb_video_adapter（时序与输出适配）
//   不变：sdram U3（加密IP，只做信号名映射）、HDMI发射器、音频链路、PLL、复位树、数码管
//   bank地址映射：bank i 基址 = i*307200（640x480=307200字/图，共4bank）
// =============================================================================
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key3,           // physical KEY3 / B1
    input [2:0]                 sw_eq,          // SW2/C7, SW3/C6, SW4/C5
    input                       sw_volume,      // physical SW1 / C8, up = volume keys
    input                       key2,           // 自动播放 开/关

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480（第8课：bank基址在loader/reader内部计算）

// 音频通过FAT32文件读取：SONG1.WAV..SONG16.WAV，与PIC1.BMP..PIC16.BMP对应。
// 文件必须是44字节标准头的48kHz/16bit/双声道PCM WAV。

// Declare domain resets and route/frame handshakes before every consumer.
wire        frame_start_raw;     // vsync下降沿（帧消隐期开始）
wire sys_rst_n, sdcard_rst_n, mem_rst_n, video_rst_n, hdmi5x_rst_n;
wire sys_rst, sdcard_rst, mem_rst, video_rst, hdmi5x_rst;
wire accepted_manual,manual_same_song;

wire Sdr_init_done;
reg sdr_init_sd1,sdr_init_sd2;
wire Sdr_init_ref_vld;
wire Sdr_busy;
wire refresh_hold, refresh_request, refresh_fault_mem;
reg refresh_fault_sd1, refresh_fault_sd2;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

// HDMI 1.4b 相关
wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// ===================== HDMI音频（正弦波媒体音调，复用像素时钟） =====================
wire        rst_n_video;             // video_clk域低有效复位

wire        tone_valid;              // pcm_media_tone → 契约适配器
wire        tone_ready;
wire signed [15:0] tone_left;
wire signed [15:0] tone_right;
wire        tone_overflow;

wire        pcm_valid;               // 契约适配器 → HDMI核（48kHz样本选通）
wire signed [15:0] pcm_left;
wire signed [15:0] pcm_right;
wire        contract_error;

wire        acr_valid;               // ACR包（音频时钟再生，音视频同步）
wire [19:0] acr_cts;
wire [19:0] acr_n;

// ===================== 第8课新增：四bank架构内部信号 =====================
// sd_card_bmp ↔ loader（sd_card_clk域）
wire        bmp_pixel_valid;
wire [23:0] bmp_pixel_rgb;
wire        bmp_frame_commit;
wire [7:0]  bmp_decode_error;
wire [63:0] bmp_meta_width_bcd;
wire [63:0] bmp_meta_height_bcd;
wire [3:0]  bmp_meta_valid;
wire        bmp_load_start;
wire [1:0]  bmp_load_image_index;
wire        bmp_key_next_press;
wire        bmp_key_auto_press;
wire [3:0]  bmp_err_code;

// loader ↔ 写CDC（loader在sd_card_clk域，CDC转到ext_mem_clk域）
wire        loader_load_done;
wire [3:0]  loader_image_complete;
wire [7:0]  loader_memory_error;
wire        loader_wr_en;
wire [20:0] loader_wr_addr;
wire [3:0]  loader_wr_mask;
wire [31:0] loader_wr_data;

// 写CDC → SDRAM写端口（ext_mem_clk域）
wire        cdc_wr_en;
wire [20:0] cdc_wr_addr;
wire [3:0]  cdc_wr_mask;
wire [31:0] cdc_wr_data;
wire        cdc_wr_burst_active;

// reader（mem_clk=ext_mem_clk读SDRAM，pix_clk=video_clk送显示）
wire        reader_rd_en;
wire [20:0] reader_rd_addr;
wire        reader_rd_burst_active;
wire [1:0]  active_index_pix;    // 当前显示图片编号（video_clk域，帧消隐期提交）
wire [23:0] reader_rgb;
wire        reader_pixel_valid;
wire        reader_underflow;
wire [7:0]  reader_error;

// 播放控制器
wire [7:0]  control_error;
wire        auto_enabled_sd;     // 自动播放状态（sd_card_clk域，第9课接OSD）

// 第9课：OSD状态条信号（auto/media_err跨域到video_clk两级同步，准静态）
reg  [7:0]  media_err_pix1;
reg  [7:0]  media_err_pix2;
reg         auto_en_pix1;
reg         auto_en_pix2;
wire [23:0] osd_rgb_out;
wire        osd_de_out;
wire        osd_active;
reg [63:0] res_width_pix1,res_width_pix2;
reg [63:0] res_height_pix1,res_height_pix2;
reg [3:0]  res_valid_pix1,res_valid_pix2;
reg        frame_start_meta;
reg [15:0] resolution_width_frame,resolution_height_frame;
reg        resolution_valid_frame;
wire [23:0] resolution_rgb_out;
// 第12课：音频波形可视化叠加输出
wire [23:0] wave_rgb_out;
wire        wave_active;
// 第16课：歌词叠加输出
wire [23:0] lyric_rgb_out;
wire [23:0] lyric_input_rgb;
wire [23:0] player_ui_rgb,browser_ui_rgb,presentation_rgb;
wire [31:0] wav_sample_cnt;    // u_wav_player真实消费样本计数（下溢不计、停播清零）
// Source position includes the seek origin.
wire [31:0] wav_position;
wire [15:0] lyric_cs;

// 第13课：缩略图模式信号
reg         key2_sync0;        // KEY2电平两级同步（sd_card_clk域）
reg         key2_sync1;
reg  [28:0] key2_hold_cnt;     // 按住计时（封顶3s）
reg  [20:0] key2_rel_cnt;      // 释放稳定计时（20ms消抖窗）
reg         key2_eval_pending; // 有待评估的按压
reg  [25:0] key2_dbl_cnt;      // 双击窗口计时（0.5s）
reg         auto_revert_pulse; // 参数长按确认后撤销误触的自动翻转
wire        thumb_mode_sd;     // 缩略图模式翻转寄存器（sd_card_clk域）
reg         thumb_mode_pix1;   // → video_clk 两级同步
reg         thumb_mode_pix2;
wire        thumb_mode_frame;  // reader输出的帧边界生效模式
wire        thumb_de;          // 缩略图区有效像素（含image_complete门控，课件模块）
wire        thumb_focus_border;// 焦点格2px边框
wire        thumb_region;      // 屏幕左上320x240区域（消费门控用，不带完成位）
reg  [3:0]  imgc_pix1;         // image_complete跨域到video_clk两级同步（准静态）
reg  [3:0]  imgc_pix2;

// 第14课：亮度/对比度参数
wire  [2:0]  bright_level;      // 亮度档位0-4（sd_card_clk域，KEY2按住1.2~3s松开步进）
wire  [2:0]  contr_level;       // 对比度档位0-4（按住≥3s松开步进）
reg  [2:0]  bright_lvl_pix1;   // 档位→video_clk两级同步（准静态）
reg  [2:0]  bright_lvl_pix2;
reg  [2:0]  contr_lvl_pix1;
reg  [2:0]  contr_lvl_pix2;
reg  [7:0]  bright_q;          // 帧边界锁存后的参数（像素链用）
reg  [7:0]  contr_q;
reg  [11:0] bright_bcd_q;      // 帧边界锁存后的BCD（参数OSD用）
reg  [11:0] contr_bcd_q;
wire [23:0] adj_rgb;           // 亮度对比度调节后的像素（送OSD）
wire [23:0] param_rgb_out;     // 参数行叠加后的像素（送频谱）
wire transition_pref_sd,clean_mode_sd,image_edit_sd;
reg transition_pref_pix1,transition_pref_pix2;
reg clean_pix1,clean_pix2,clean_frame;
reg image_edit_pix1,image_edit_pix2;
reg [1:0] transition_text_q;

// 第15课：缩略图交互选择（焦点移动/快速选择/模式转场）
reg         key1_sync0;        // KEY1电平两级同步（sd_card_clk域，缩略图导航用）
reg         key1_sync1;
reg  [28:0] key1_hold_cnt;     // KEY1按住计时（缩略图下：短按=焦点右移、≥1.2s=确认）
reg  [20:0] key1_rel_cnt;
reg         key1_eval_pending;
wire         key1_nav_right;    // 缩略图焦点右移单拍脉冲
wire         key1_nav_confirm;  // 缩略图确认选择单拍脉冲
wire         key2_nav_left;     // 缩略图焦点左移单拍脉冲（KEY2单击）
wire         key2_dbl_pulse;    // 模式切换单拍脉冲（KEY2双击）
wire        ctrl_view_mode;    // thumbnail_controller期望模式（全黑时刻才应用）
wire [1:0]  ctrl_focus_index;  // 焦点位置（sd域）
wire        ctrl_transition_req;
reg         fs_sd1, fs_sd2;    // frame_start_raw同步到sd域（供controller帧边界）
wire        sel_pending;       // 确认/模式切换待应用（等转场全黑时刻）
wire [1:0]  sel_index;         // 锁存的目标图片号（确认=焦点图；模式切换=当前图）
reg  [1:0]  focus_idx_pix1;    // 焦点跨域到video_clk两级同步
reg  [1:0]  focus_idx_pix2;
wire [3:0] ctrl_focus_track;
wire bmp_load_menu,menu_ready_sd,menu_mode_frame;
wire [1:0] menu_page_frame;
reg menu_ready_pix1,menu_ready_pix2;
reg [3:0] browser_focus_pix1,browser_focus_pix2,browser_focus_q;
reg [15:0] browse_valid_pix1,browse_valid_pix2,browse_valid_q;
wire [3:0] browse_page_valid=menu_mode_frame?(browse_valid_q>>{menu_page_frame,2'b00}):imgc_pix2;
assign ctrl_focus_index=ctrl_focus_track[1:0];
reg  [1:0]  focus_idx_q;       // 帧边界锁存后的焦点（thumbnail_layout用，边框不撕裂）

// Declare route signals before the control/fade instances that consume them.
wire transition_busy;
wire eq_clipped;
wire manual_track_request;
wire manual_found;
wire sequence_advance;

// 第10课：转场控制信号
wire        fade_next_event;   // 转场控制器全黑时刻放行的切换请求（sd_card_clk域）
wire        index_commit_pix;  // u_control的索引提交脉冲（video_clk域）
wire [7:0]  fade_alpha;        // 淡入淡出alpha（0-255）
wire        wipe_active;       // Wipe揭示进行中
wire [4:0]  wipe_ramp;         // Wipe边界计数（帧数）
wire [15:0] fade_mult_r;       // alpha乘法中间积
wire [15:0] fade_mult_g;
wire [15:0] fade_mult_b;
wire [23:0] faded_rgb;         // alpha乘法后的像素
wire [9:0]  wipe_boundary;     // Wipe边界X坐标
wire [23:0] transition_rgb;    // 转场后的像素（送OSD）

// 第11课：WAV音频播放信号
wire sd_free;
// SDRAM initialization originates in ext_mem_clk. Synchronize once before
// SD-domain scan/loader control rather than crossing into FIFO/error logic.
always @(posedge sd_card_clk or negedge sdcard_rst_n)begin
    if(!sdcard_rst_n)begin sdr_init_sd1<=0;sdr_init_sd2<=0;end
    else begin sdr_init_sd1<=Sdr_init_done;sdr_init_sd2<=sdr_init_sd1;end
end
wire [15:0] library_catalog_playable,library_playable;
wire [1:0] library_cache_page,library_target_page,library_cover_slot;
wire library_page_start,library_page_done,library_cache_invalidate;
wire library_route_busy,library_sequence_ready,library_audio_allowed;
wire library_fade_request,library_cover_select,library_load_failed,library_abort_toggle;
wire library_control_busy,ctrl_transition_select;
wire library_keep_valid;wire [1:0] library_keep_slot;
wire library_nav_busy,library_nav_done;
wire [3:0] library_current_track,library_pending_track;
reg [3:0] library_track_pix;
reg library_abort_s1,library_abort_s2,library_abort_seen,library_abort_pending,library_abort_pulse;
reg library_display_s1,library_display_s2,library_video_armed;
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin
  library_track_pix<=0;library_abort_s1<=0;library_abort_s2<=0;
  library_abort_seen<=0;library_abort_pending<=0;library_abort_pulse<=0;
  library_display_s1<=0;library_display_s2<=0;library_video_armed<=0;
 end else begin
  library_abort_s1<=library_abort_toggle;library_abort_s2<=library_abort_s1;
  // 显示解锁=音画放行且"当前显示槽"已就绪：不再用sd_free（整页载完）门控——
  // 旧写法把跨页提前放行（选中槽先就绪即切）整页屏蔽到页末，实机表现为
  // 跨页黑屏~2s、封面与音乐同来。提交链只切到image_complete已置位的槽，
  // 故按显示槽判定即可；该槽被重写前其完成位已先清（loader逐槽/整页失效），不会显示半成品。
  library_display_s1<=library_audio_allowed && loader_image_complete[active_index_pix];
  library_display_s2<=library_display_s1;
  if(!library_display_s2)library_video_armed<=0;
  else if(frame_start_raw)library_video_armed<=1;
  library_abort_pulse<=0;
  if(library_abort_s2!=library_abort_seen)begin
   library_abort_seen<=library_abort_s2;library_abort_pending<=1;
  end
  if(frame_start_raw&&library_abort_pending)begin library_abort_pending<=0;library_abort_pulse<=1;end
  if(index_commit_pix||library_abort_pulse)library_track_pix<=library_pending_track;
 end
end
           // sd_card_bmp首轮加载结束，SD卡空闲（sd_card_clk域）
wire [3:0]  song_valid;
wire [31:0] song_cluster0, song_cluster1, song_cluster2, song_cluster3;
wire [31:0] song_size0, song_size1, song_size2, song_size3;
wire [3:0] lrc_valid;
wire [31:0] lrc_cluster0,lrc_cluster1,lrc_cluster2,lrc_cluster3;
wire [31:0] lrc_size0,lrc_size1,lrc_size2,lrc_size3;
wire font_valid;
wire [31:0] font_cluster,font_size;
wire lyric_sector_mode;
wire lyric_file_start,lyric_file_done,lyric_file_valid;
wire [7:0] lyric_file_byte,lyric_file_error;
wire [31:0] lyric_first_cluster,lyric_file_size,lyric_file_offset,lyric_start_offset;
wire lyric_file_partial;
wire lyric_ready_for_song,lyric_visible;
// LYRIC_READY_EXPORT_BEGIN
// Register readiness before its video-domain synchronizer. Keep the audio
// start handshake unchanged and remove metadata decoding from the CDC path.
reg lyric_visible_export;
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if(!sdcard_rst_n) lyric_visible_export <= 1'b0;
    else lyric_visible_export <= lyric_visible;
end
// LYRIC_READY_EXPORT_END
wire [7:0] live_cue_count,live_cue_index;
wire live_font_we,live_text_we,live_cue_we;
wire [11:0] live_font_addr;
wire [11:0] live_text_addr,live_cue_base;
wire [11:0] lyric_timing_addr;
wire [7:0] lyric_timing_data;
wire lyric_timing_ready;
wire [15:0] live_font_data,live_cue_start;
wire [7:0] live_text_data;
wire [4:0] live_cue_len;
wire live_title_we;
wire [4:0] live_title_addr,live_title_count;
wire [7:0] live_title_data;
wire [7:0]  media_spc;
wire [31:0] media_fat_start, media_data_start, media_max_cluster;
reg         wav_play_en;
reg  [26:0] wav_restart_cnt;
// WAV_RUN出错时进WAV_GAP并载100M(约1s),倒数到0经eof自动跳下一首(原设计WAV_ERROR死等人工干预=卡住)
wire        wav_stream_end;
wire        wav_stream_active;
reg         wav_active_pix1;   // stream_active跨域到video_clk两级同步
reg         wav_active_pix2;
// WAV文件流接口（sd_card_clk域，字节流来自sd_card_bmp内共享流读器owner=2）
wire        wav_sector_busy;
// WAV读侧（video_clk域）
reg  [24:0] wav_tick_acc;      // 48kHz采样tick Bresenham累加器（与pcm_media_tone同款）
wire        wav_sample_tick;
wire signed [15:0] wav_left_out, wav_right_out;
wire        wav_sample_valid;
wire        wav_sample_ready;
wire signed [23:0] wav_gain_left, wav_gain_right;
wire signed [15:0] wav_left_gained, wav_right_gained;
wire        wav_format_error;
wire        wav_can_read_sector;
wire        wav_file_busy, wav_file_done, wav_file_valid;
wire [7:0]  wav_file_byte, wav_file_error;
wire [31:0] wav_file_offset;
reg         wav_file_start;
reg  [1:0]  selected_song;
localparam [3:0] WAV_WAIT=0, WAV_STOP=1, WAV_START=2,
                 WAV_RUN=3, WAV_GAP=4, WAV_ERROR=5, WAV_ENDED=6,
                 WAV_SEEK_FADE=7,WAV_SEEK_STOP=8,WAV_SEEK_PREP=9,WAV_SEEK_START=10;
reg [3:0] wav_control_state;
reg         wav_end_sd1, wav_end_sd2;
wire [31:0] selected_song_cluster = selected_song == 2'd0 ? song_cluster0 :
                                    selected_song == 2'd1 ? song_cluster1 :
                                    selected_song == 2'd2 ? song_cluster2 : song_cluster3;
wire [31:0] selected_song_size = selected_song == 2'd0 ? song_size0 :
                                 selected_song == 2'd1 ? song_size1 :
                                 selected_song == 2'd2 ? song_size2 : song_size3;
// SEEK_TRANSPORT_BEGIN
reg lyric_ready_q;
reg [31:0] wav_origin_sd;
reg [31:0] wav_start_offset;
reg wav_seek_restart;
reg seek_stream_ready;
reg [31:0] seek_target /* fehdl keep="true" */;
reg [31:0] seek_plus /* fehdl keep="true" */;
reg seek_under,seek_hi_gt,seek_hi_eq,seek_lo_ge;
reg seek_back_q;
reg [2:0] seek_calc;
wire seek_hold_sd=wav_control_state>=WAV_SEEK_FADE;
reg seek_hold_p1,seek_hold_p2,seek_muted_s1,seek_muted_s2;
reg [7:0] seek_gain;
reg seek_gain_step;
reg [31:0] seek_sample_snapshot;
reg seek_hold_q;
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin seek_hold_p1<=0;seek_hold_p2<=0;seek_gain<=255;seek_gain_step<=0;seek_sample_snapshot<=0;seek_hold_q<=0;end
 else begin
  seek_hold_p1<=seek_hold_sd;seek_hold_p2<=seek_hold_p1;
  seek_hold_q<=seek_hold_p2;
  if(seek_hold_p2 && !seek_hold_q)seek_sample_snapshot<=wav_sample_cnt;
  if(wav_sample_tick)begin
   seek_gain_step<=!seek_gain_step;
   if(seek_gain_step)begin
    if(seek_hold_p2 && seek_gain!=0)seek_gain<=seek_gain-1'b1;
    else if(!seek_hold_p2 && seek_gain!=255)seek_gain<=seek_gain+1'b1;
   end
  end
 end
end
always @(posedge sd_card_clk or posedge sdcard_rst)begin
 if(sdcard_rst)begin seek_muted_s1<=0;seek_muted_s2<=0;end
 else begin
  seek_muted_s1<=seek_hold_p2 && seek_hold_q && seek_gain==0;seek_muted_s2<=seek_muted_s1;
 end
end
// SEEK_TRANSPORT_END

// Canonical 44-byte, 48 kHz, 16-bit stereo WAV prepared by the card tool.
// Publish a stable bundle once per file start; the toggle crosses first,
// then the video side captures the bundle, held until the next file start.
reg [31:0] ui_frames_sd,ui_frames_pix;
// Capture the descriptor on file_start, then publish one SD clock later.
// This separates the size mux from subtracting the 11 stereo-frame header.
reg ui_size_good_sd,ui_length_pending;
reg [3:0] ui_song_pending;

reg [31:0] wav_origin_pix;
reg [3:0] ui_song_sd,ui_song_pix;
reg ui_length_toggle,ui_length_pix1,ui_length_pix2,ui_length_seen;
wire [31:0] ui_total_frames = ui_song_pix == library_track_pix ? ui_frames_pix : 32'd0;
always @(posedge sd_card_clk or posedge sdcard_rst) begin
    if (sdcard_rst) begin ui_frames_sd<=0;ui_song_sd<=0;ui_length_toggle<=0;ui_length_pending<=0;end
    else begin
        ui_length_pending<=wav_file_start;
        if(wav_file_start)begin
            ui_frames_sd<={2'b0,selected_song_size[31:2]};
            ui_size_good_sd<=selected_song_size>44;
            ui_song_pending<={library_cache_page,selected_song};
        end
        if(ui_length_pending)begin
            ui_frames_sd<=ui_size_good_sd ? {2'b0,(ui_frames_sd[29:0]-30'd11)} : 0;
            ui_song_sd<=ui_song_pending;
            ui_length_toggle<=!ui_length_toggle;
        end
    end
end
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        ui_frames_pix<=0;ui_song_pix<=0;ui_length_pix1<=0;wav_origin_pix<=0;
        ui_length_pix2<=0;ui_length_seen<=0;
    end else begin
        ui_length_pix1<=ui_length_toggle;ui_length_pix2<=ui_length_pix1;
        if (ui_length_pix2!=ui_length_seen) begin
            ui_length_seen<=ui_length_pix2;
            ui_frames_pix<=ui_frames_sd;ui_song_pix<=ui_song_sd;wav_origin_pix<=wav_origin_sd;
        end
    end
end
wire        fade_active;       // 第10课转场进行中（原悬空，第11课接sync_fade_gain）
wire [7:0]  gain_aud;          // 音频增益包络（0-255，转场时=alpha，空闲=255）
// 音源mux → 契约适配器
wire        mux_valid;
wire        mux_ready;
wire signed [15:0] mux_left;
wire signed [15:0] mux_right;

// 视频时序（video_timing_ctrl输出，未寄存）
wire        raw_hs;
wire        raw_vs;
wire        raw_de;
wire [11:0] raw_x;
wire [11:0] raw_y;
reg         raw_vs_q;

reg         img0_done_sync0;     // bank0加载完成标记跨域：sd_card_clk → video_clk
reg         img0_done_sync1;
wire        player_enable_pix;   // 首图就绪前黑屏（替代旧display_valid）
wire        frame_start;         // 使能后的帧起始（reader用）
wire        pixel_consume;       // 像素消费（使能后的de）
wire [23:0] selected_rgb;        // 像素无效时强制黑（消隐防护之外的下溢防护）

// 错误码跨域汇聚（数码管调试，sd_card_clk域）
reg  [7:0]  reader_error_sd1;
reg  [7:0]  reader_error_sd2;
reg         underflow_sd1;
reg         underflow_sd2;
reg  [1:0]  active_idx_sd1;
reg  [1:0]  active_idx_sd2;
wire [7:0]  media_err;

// 统一复位：TF 图像链路 + HDMI 链路
wire sys_pll_lock;
wire video_pll_lock;
wire rst_all;

reg [19:0] rst_cnt = 20'd0;
reg rst_all_reg = 1'b1;

always @(posedge clk) begin
    if (!rst_n) begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end else if (!rst_all_reg) begin
        // 一旦复位释放，忽略后续微小的 PLL 抖动，防止系统在使用时随机复位
        rst_all_reg <= 1'b0;
    end else if (sys_pll_lock && video_pll_lock) begin
        // 等待 PLL 连续稳定 20ms @ 50MHz
        if (rst_cnt < 20'd1_000_000) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_all_reg <= 1'b1;
        end else begin
            rst_all_reg <= 1'b0;
        end
    end else begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end
end

assign rst_all = rst_all_reg;

// ===================== 第5课：复位同步器（异步复位，同步释放） =====================
// 每个时钟域一个实例，消除复位释放瞬间的亚稳态（官方是异步复位异步释放）
// rst_all已含：外部按键 + sys/video双PLL锁定 + 20ms上电延时（比第5课最小方案更完善，保留）
wire rst_src_n;



assign rst_src_n  = ~rst_all;
assign sys_rst    = ~sys_rst_n;
assign sdcard_rst = ~sdcard_rst_n;
assign mem_rst    = ~mem_rst_n;
assign video_rst  = ~video_rst_n;
assign hdmi5x_rst = ~hdmi5x_rst_n;

reset_sync u_sys_reset    (.clk(clk),          .ext_rst_n(rst_src_n), .rst_n_sync(sys_rst_n));
reset_sync u_sdcard_reset (.clk(sd_card_clk),  .ext_rst_n(rst_src_n), .rst_n_sync(sdcard_rst_n));
reset_sync u_mem_reset    (.clk(ext_mem_clk),  .ext_rst_n(rst_src_n), .rst_n_sync(mem_rst_n));
reset_sync u_video_reset  (.clk(video_clk),    .ext_rst_n(rst_src_n), .rst_n_sync(video_rst_n));
reset_sync u_hdmi5x_reset (.clk(hdmi_5x_clk),  .ext_rst_n(rst_src_n), .rst_n_sync(hdmi5x_rst_n));

// TF/控制侧50MHz；SDRAM125MHz与video时钟保持原设置。
sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (~rst_n),   // 第5课修改：原来接1'b0，外部复位时PLL也复位重新锁定
    .extlock    (sys_pll_lock),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (~rst_n),   // 第5课修改：原来接1'b0
    .extlock    (video_pll_lock),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

// ===================== TF卡FAT32扫描 + BMP像素流 + 顺序加载（第8课改四bank） =====================
// RESUME_INTEGRATION_BEGIN
wire checkpoint_boot_ready,checkpoint_restore_valid,checkpoint_enabled,checkpoint_error;
wire [3:0] checkpoint_restore_track;
wire [31:0] checkpoint_restore_frame,checkpoint_restore_size,checkpoint_restore_cluster;
wire resume_hold_audio,resume_route_request,resume_apply,resume_ready;
wire [3:0] resume_route_target;
// RESUME_VALIDATION_BEGIN
wire resume_position_ready,resume_position_valid;
wire [31:0] resume_start_offset;
wire resume_position_ok=resume_apply && resume_position_ready && resume_position_valid;
resume_file_validator u_resume_validator(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),
 .check_req(resume_apply && wav_control_state==WAV_STOP && active_idx_sd2==selected_song && song_valid[selected_song]),
 .actual_size(selected_song_size),.actual_cluster(selected_song_cluster),
 .saved_size(checkpoint_restore_size),.saved_cluster(checkpoint_restore_cluster),.saved_frame(checkpoint_restore_frame),
 .ready(resume_position_ready),.valid(resume_position_valid),.start_offset(resume_start_offset)
);
// RESUME_VALIDATION_END
wire resume_consumed=wav_control_state==WAV_STOP && lyric_ready_q && !wav_sector_busy &&
 active_idx_sd2==selected_song && song_valid[selected_song] && (!resume_apply || resume_position_ready);
resume_startup u_resume_startup(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),.boot_ready(checkpoint_boot_ready),.record_valid(checkpoint_restore_valid),
 .record_track(checkpoint_restore_track),.playable(library_catalog_playable),
 .route_ready(library_sequence_ready),.manual_accepted(accepted_manual),.current_track(library_current_track),
 .consumed(resume_consumed),.user_cancel(resume_ready && (manual_track_request || ctrl_transition_req)),
 .hold_audio(resume_hold_audio),.route_request(resume_route_request),.route_target(resume_route_target),
 .apply_position(resume_apply),.ready(resume_ready)
);
// Transfer position + track + file-start epoch. File descriptors are already
// stable in the SD domain. Matching both track and epoch excludes stale
// positions after a same-song restart without duplicating 64 metadata bits.
wire [37:0] checkpoint_snapshot;
checkpoint_snapshot_cdc u_checkpoint_snapshot(
 .src_clk(video_clk),.src_rst_n(video_rst_n),.dst_clk(sd_card_clk),.dst_rst_n(sdcard_rst_n),
 .source_bundle({wav_active_pix2 && wav_sample_cnt>=1024 && !seek_hold_p2 &&
                 ui_song_pix==library_track_pix,ui_length_seen,ui_song_pix,wav_position}),
 .destination_bundle(checkpoint_snapshot)
);
wire checkpoint_snapshot_good=checkpoint_snapshot[37] && resume_ready && wav_control_state==WAV_RUN &&
 !wav_file_start && !ui_length_pending &&
 !library_route_busy && !transition_busy && checkpoint_snapshot[35:32]==library_current_track &&
 checkpoint_snapshot[36]==ui_length_toggle;
// RESUME_INTEGRATION_END
sd_card_bmp #(
    .CLK_FREQ_HZ       (50_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4),.MENU_SUPPORT(1)
) sd_card_bmp_m0(
    .checkpoint_snapshot_valid(checkpoint_snapshot_good),.checkpoint_snapshot_track(checkpoint_snapshot[35:32]),
    .checkpoint_snapshot_frame(checkpoint_snapshot[31:0]),.checkpoint_snapshot_size(selected_song_size),
    .checkpoint_snapshot_cluster(selected_song_cluster),
    .checkpoint_boot_ready(checkpoint_boot_ready),.checkpoint_restore_valid(checkpoint_restore_valid),
    .checkpoint_restore_track(checkpoint_restore_track),.checkpoint_restore_frame(checkpoint_restore_frame),
    .checkpoint_restore_size(checkpoint_restore_size),.checkpoint_restore_cluster(checkpoint_restore_cluster),
    .checkpoint_enabled(checkpoint_enabled),.checkpoint_error(checkpoint_error),
    .clk               (sd_card_clk),
    .rst               (sdcard_rst),
    .sdr_init_done     (sdr_init_sd2),
    .key_next          (key1),
    .key_auto          (key2),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),

    // 第8课：像素流 → media_frame_loader
    .menu_ready(menu_ready_sd),.load_menu(bmp_load_menu),
    .pixel_valid       (bmp_pixel_valid),
    .pixel_rgb         (bmp_pixel_rgb),
    .frame_commit      (bmp_frame_commit),
    .decode_error      (bmp_decode_error),
    .meta_width_bcd    (bmp_meta_width_bcd),
    .meta_height_bcd   (bmp_meta_height_bcd),
    .meta_valid        (bmp_meta_valid),

    // 第8课：加载控制 ↔ media_frame_loader
    .load_start        (bmp_load_start),
    .load_image_index  (bmp_load_image_index),
    .loader_load_done  (loader_load_done),
    .loader_memory_error(loader_memory_error),
    .image_complete    (loader_image_complete),

    // 第8课：按键脉冲 → media_player_control
    .key_next_press    (bmp_key_next_press),
    .key_auto_press    (bmp_key_auto_press),

    .err_code          (bmp_err_code),

    // 第11课：WAV播放器SD扇区接口（SEQ_DONE后独占SD卡）
    .sd_free           (sd_free),
    .page_start(library_page_start),.requested_page(library_target_page),
    .requested_slot(library_cover_slot),   // 选中封面优先加载的起始槽
    .active_page(library_cache_page),.library_playable(library_catalog_playable),
    .page_done(library_page_done),.cache_invalidate(library_cache_invalidate),
    .song_valid        (song_valid),
    .song0_cluster     (song_cluster0),
    .song1_cluster     (song_cluster1),
    .song2_cluster     (song_cluster2),
    .song3_cluster     (song_cluster3),
    .song0_size        (song_size0),
    .song1_size        (song_size1),
    .song2_size        (song_size2),
    .song3_size        (song_size3),
    .lrc_valid         (lrc_valid),
    .lrc0_cluster      (lrc_cluster0),
    .lrc1_cluster      (lrc_cluster1),
    .lrc2_cluster      (lrc_cluster2),
    .lrc3_cluster      (lrc_cluster3),
    .lrc0_size         (lrc_size0),
    .lrc1_size         (lrc_size1),
    .lrc2_size         (lrc_size2),
    .lrc3_size         (lrc_size3),
    .font_valid        (font_valid),
    .font_cluster      (font_cluster),
    .font_size         (font_size),
    .media_sectors_per_cluster(media_spc),
    .media_fat_start_lba(media_fat_start),
    .media_data_start_lba(media_data_start),
    .media_max_cluster (media_max_cluster),
    // 共享流读器（封面/歌词/WAV三客户端复用，SEQ_DONE后WAV/歌词独占）
    .wav_sector_busy   (wav_sector_busy),
    .wav_play_en       (wav_play_en),
    .wav_can_read_sector(wav_can_read_sector),
    .wav_file_start    (wav_file_start),
    .wav_first_cluster (selected_song_cluster),
    .wav_file_size     (selected_song_size),
    .wav_start_offset  (wav_start_offset),
    .wav_file_busy     (wav_file_busy),
    .wav_file_done     (wav_file_done),
    .wav_file_valid    (wav_file_valid),
    .wav_file_byte     (wav_file_byte),
    .wav_file_offset   (wav_file_offset),
    .wav_file_error    (wav_file_error),
    .lyric_sector_mode (lyric_sector_mode),
    .lyric_file_start  (lyric_file_start),
    .lyric_first_cluster(lyric_first_cluster),
    .lyric_file_size   (lyric_file_size),
    .lyric_start_offset(lyric_start_offset),.lyric_file_partial(lyric_file_partial),
    .lyric_file_done   (lyric_file_done),
    .lyric_file_valid  (lyric_file_valid),
    .lyric_file_byte   (lyric_file_byte),
    .lyric_file_offset (lyric_file_offset),
    .lyric_file_error  (lyric_file_error),

    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// ===================== 第8课新增：media_frame_loader（帧加载器，sd_card_clk域） =====================
// 内部：512字FIFO缓存像素流、128字burst写、四bank基址、垂直翻转、6个错误码
media_frame_loader #(
    .ADDR_WIDTH(21),
    .IMAGE_WORDS(307200),
    .FIFO_DEPTH(512),
    .BURST_SIZE(128),
    .STALL_TIMEOUT(65535),
    .WRITE_V_FLIP(1),
    .FRAME_WIDTH(640),
    .FRAME_HEIGHT(480),.MENU_SUPPORT(1)
) u_loader (
    .clk                 (sd_card_clk),
    // 页失效改由cache_invalidate软清完成位（keep_slot槽保留），不再整模块硬复位——
    // 重叠加载时旧封面槽内容仍在被显示读取，硬复位清完成位会把淡出瞬间拉黑。
    .rst_n               (sdcard_rst_n),
    .cache_invalidate    (library_cache_invalidate),
    .keep_valid          (library_keep_valid),
    .keep_slot           (library_keep_slot),
    .load_start          (bmp_load_start),
    .image_index         (bmp_load_image_index),.menu_load(bmp_load_menu),
    .pixel_valid         (bmp_pixel_valid),
    .pixel_rgb           (bmp_pixel_rgb),
    .frame_commit        (bmp_frame_commit),
    .decode_error        (bmp_decode_error),
    .load_busy           (),
    .load_done           (loader_load_done),
    .image_complete      (loader_image_complete),
    .memory_error        (loader_memory_error),
    .controller_init_done(sdr_init_sd2),
    .controller_busy     (Sdr_busy),
    .refresh_active      (Sdr_init_ref_vld),
    .app_wr_en           (loader_wr_en),
    .app_wr_addr         (loader_wr_addr),
    .app_wr_mask         (loader_wr_mask),
    .app_wr_data         (loader_wr_data)
);

// ===================== 第8课新增：写命令跨时钟域（100M→125M，写优先互斥） =====================
media_sdram_write_cdc #(
    .ADDR_WIDTH(21),
    .FIFO_ADDR_WIDTH(9),
    .BURST_SIZE(128)
) u_write_cdc (
    .src_clk           (sd_card_clk),
    .src_rst_n         (sdcard_rst_n),
    .src_wr_en         (loader_wr_en),
    .src_wr_addr       (loader_wr_addr),
    .src_wr_mask       (loader_wr_mask),
    .src_wr_data       (loader_wr_data),
    .src_full          (),
    .src_overflow      (),
    .dst_clk           (ext_mem_clk),
    .dst_rst_n         (mem_rst_n),
    .rd_burst_active   (reader_rd_burst_active),
    .refresh_hold      (refresh_hold),
    .dst_app_wr_en     (cdc_wr_en),
    .dst_app_wr_addr   (cdc_wr_addr),
    .dst_app_wr_mask   (cdc_wr_mask),
    .dst_app_wr_data   (cdc_wr_data),
    .wr_burst_active   (cdc_wr_burst_active),
    .dst_idle          ()
);

// ===================== 第8课新增：media_frame_reader（帧读取器） =====================
// mem_clk域发起128字burst读（最多2个在飞），异步FIFO跨域，prefetch预取防下溢
media_frame_reader #(
    .FRAME_ENABLE_CONTROL(1),.MENU_SUPPORT(1),
    .ADDR_WIDTH(21),
    .IMAGE_WORDS(307200),
    .FIFO_DEPTH(512),
    .FIFO_MARGIN(16),     // 默认8；改16仅为扰动布局重掷hold（保留深度仍远大于2x128在飞量）
    .BURST_SIZE(128),
    .BURST_GAP_CYCLES(12),
    .MAX_INFLIGHT_BURSTS(2),
    .DIAG_RETURN_PATTERN(0),
    .DIAG_SYNTH_STREAM(0)
) u_reader (
    .mem_clk             (ext_mem_clk),
    .mem_rst_n           (mem_rst_n),
    .controller_init_done(Sdr_init_done),
    .controller_busy     (Sdr_busy),
    .refresh_active      (Sdr_init_ref_vld || refresh_hold),
    .app_rd_en           (reader_rd_en),
    .app_rd_addr         (reader_rd_addr),
    .sdram_rd_valid      (Sdr_rd_en),       // 信号名映射：Sdr_rd_en=读数据有效
    .sdram_rd_data       (Sdr_rd_dout),
    .wr_burst_active     (cdc_wr_burst_active),
    .rd_burst_active     (reader_rd_burst_active),
    .pix_clk             (video_clk),
    .pix_rst_n           (video_rst_n),
    .frame_start(frame_start_raw),.frame_enable(library_display_s2),
    .active_index        (active_index_pix),
    .thumb_mode          (thumb_mode_pix2),     // 第13课：缩略图模式（帧边界生效）
    .thumb_mode_frame    (thumb_mode_frame),
    .menu_ready(menu_ready_pix2 && !image_edit_pix2),.menu_page(browser_focus_q[3:2]),
    .menu_mode_frame(menu_mode_frame),.menu_page_frame(menu_page_frame),
    .pixel_consume       (pixel_consume),
    .pixel_rgb           (reader_rgb),
    .pixel_valid         (reader_pixel_valid),
    .underflow           (reader_underflow),
    .reader_busy         (),
    .frame_read_done     (),
    .reader_index        (),
    .reader_error        (reader_error)
);

// ===================== 第8课新增：media_player_control（播放控制器） =====================
// sys_clk域收切换请求（只切到image_complete已置位的bank），
// pix_clk域在frame_start提交active_index——帧消隐期切换，无撕裂零延迟
media_player_control #(
    .DEFAULT_PERIOD_CYCLES(32'd300_000_000),  // 默认轮播周期3秒@100MHz（与原AUTO_PLAY_MS一致）
    .MIN_PERIOD_CYCLES(32'd50_000_000),
    .MAX_PERIOD_CYCLES(32'd3_000_000_000)
) u_control (
    .sys_clk          (sd_card_clk),
    .sys_rst_n        (sdcard_rst_n),
    .next_event(1'b0),
    .select_event(library_cover_select),
    .select_index(library_cover_slot),
    .toggle_auto_event(1'b0),  // 第15课：自动翻转仅全屏生效（缩略图下单击=焦点左移）
    .period_cfg_valid (1'b0),
    .period_cfg_cycles(32'd0),
    .auto_cfg_valid   (1'b1),
    .auto_cfg_enabled (1'b0),
    .image_complete   (loader_image_complete),
    .auto_enabled     (auto_enabled_sd),
    .active_period_cycles(),
    .pending_index    (),
    .control_error    (control_error),
    .request_busy(library_control_busy),
    .pix_clk          (video_clk),
    .pix_rst_n        (video_rst_n),
    .frame_start      (frame_start_raw),   // 控制器用未门控的帧起始（提交时机与reader一致）
    .active_index     (active_index_pix),
    .index_commit     (index_commit_pix)   // 第10课：提交脉冲送转场控制器（判自动切换）
);

// ===================== 第10课新增：video_fade_transition（转场控制器） =====================
// 拦截手动"下一张"：先淡出到全黑，全黑时刻才放行切换请求给u_control，再从黑淡入；
// 自动轮播无法预知（u_control内部发起），检测到index_commit后走左→右Wipe揭示新图。
// ramp只在frame_start更新，整帧alpha/Wipe边界统一，不撕裂
video_fade_transition #(
    .FADE_FRAMES(16)   // 16帧≈0.27秒@60fps；STEP=16每帧alpha变化16
) u_fade_transition (
    .ctrl_clk       (sd_card_clk),
    .ctrl_rst_n     (sdcard_rst_n),
    .next_event_in(library_fade_request),
    .next_event_out (fade_next_event),
    .fade_busy      (transition_busy),
    .pix_clk        (video_clk),
    .pix_rst_n      (video_rst_n),
    .player_active(1'b1),
    .frame_start(frame_start_raw),
    .index_commit(index_commit_pix || library_abort_pulse),
    .auto_commit_mask(thumb_mode_frame),  // 第15课：缩略图显示中自动轮播换图不放Wipe（S_HOLD退出不受影响）
    .active_index   (active_index_pix),
    .alpha_out      (fade_alpha),
    .fade_active    (fade_active),     // 第11课：接sync_fade_gain（音画同步）
    .wipe_active    (wipe_active),
    .ramp_out       (wipe_ramp),
    .transition_kind(),
    .manual_wipe    (transition_pref_pix2)
);

// ===================== 第8课新增：video_timing_ctrl（替换video_timing_data） =====================
video_timing_ctrl #(
    .H_ACT(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
    .V_ACT(480), .V_FP(10), .V_SYNC(2), .V_BP(33),
    .ACTIVE_LAST(0)   // 标准段序：有效区在前，与官方color_bar一致
) u_timing (
    .pclk  (video_clk),
    .rst_n (video_rst_n),
    .hsync (raw_hs),
    .vsync (raw_vs),
    .de    (raw_de),
    .x     (raw_x),
    .y     (raw_y)
);

// frame_start = vsync下降沿（帧消隐期开始）
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) raw_vs_q <= 1'b1;
    else           raw_vs_q <= raw_vs;
end
assign frame_start_raw = raw_vs_q && !raw_vs;

// 首图（bank0）加载完成前黑屏；loader在sd_card_clk域，跨域到video_clk两级同步
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        img0_done_sync0 <= 1'b0;
        img0_done_sync1 <= 1'b0;
    end else begin
        img0_done_sync0 <= |loader_image_complete;
        img0_done_sync1 <= img0_done_sync0;
    end
end
assign player_enable_pix = library_video_armed;

// 第9课：OSD状态跨域（sd_card_clk→video_clk，准静态状态量，两级触发器同步）
// media_err在sd域汇聚（见数码管段），auto_enabled_sd来自media_player_control
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        media_err_pix1 <= 8'd0;
        media_err_pix2 <= 8'd0;
        auto_en_pix1   <= 1'b0;
        auto_en_pix2   <= 1'b0;
    end else begin
        media_err_pix1 <= media_err;
        media_err_pix2 <= media_err_pix1;
        auto_en_pix1   <= auto_enabled_sd;
        auto_en_pix2   <= auto_en_pix1;
    end
end
assign frame_start   = frame_start_raw && player_enable_pix;

// Unified physical KEY2/3/4 gestures; see playback_controls.v.
wire user_next,user_previous,user_mode_next,playback_paused;
wire user_seek_back,user_seek_forward,seek_mode_sd;
wire [4:0] user_volume;
wire volume_mode_sd;
wire [2:0] eq_bass,eq_mid,eq_treble;
wire [3:0] eq_edit_target;
wire [1:0] lyric_alpha_sd;wire [2:0] lyric_position_sd;
wire [1:0] lyric_alpha_p2;wire [2:0] lyric_position_p2;
wire [4:0] lyric_settings_bundle;
assign image_edit_sd=(eq_edit_target==3'd6)||(eq_edit_target==3'd7);
assign manual_track_request=library_nav_done&&manual_found&&!transition_busy&&!sel_pending;
wire [3:0] playable_slots=loader_image_complete & song_valid;
wire [3:0] manual_target;
library_neighbor_finder u_library_neighbor(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),
 .request((user_next||user_previous)&&!transition_busy&&!sel_pending),
 .previous(user_previous),.current(library_current_track),.playable(library_playable),
 .busy(library_nav_busy),.done(library_nav_done),.found(manual_found),.target(manual_target)
);

playback_controls #(.CLOCK_HZ(50_000_000)) u_playback_controls(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),
 .key_next_n(key1),.key_pause_n(key3),.key_view_n(key2),.thumbnail(thumb_mode_sd),.volume_switch(sw_volume),.eq_switches(sw_eq),
 .next_song(user_next),.previous_song(user_previous),.mode_next(user_mode_next),
 .thumb_right(key1_nav_right),.thumb_left(key2_nav_left),
 .thumb_confirm(key1_nav_confirm),.thumb_toggle(key2_dbl_pulse),
 .paused(playback_paused),.volume(user_volume),
 .brightness(bright_level),.contrast(contr_level),.volume_mode(volume_mode_sd),
 .bass(eq_bass),.mid(eq_mid),.treble(eq_treble),.edit_target(eq_edit_target),
 .seek_backward(user_seek_back),.seek_forward(user_seek_forward),.seek_mode(seek_mode_sd),
 .transition_pref(transition_pref_sd),.clean_mode(clean_mode_sd),
 .lyric_alpha(lyric_alpha_sd),.lyric_position(lyric_position_sd)
);
wire [1:0] play_mode;
wire sequence_replay,playlist_stopped;
wire [3:0] sequence_target;

reg manual_eof_cancel,manual_replay_pending;
always @(posedge sd_card_clk or posedge sdcard_rst) begin
 if(sdcard_rst) begin manual_eof_cancel<=0;manual_replay_pending<=0;end
 else begin
  if(wav_file_start && !wav_seek_restart) begin manual_eof_cancel<=0;manual_replay_pending<=0;end
  if(accepted_manual) begin
   manual_eof_cancel<=1;
   manual_replay_pending<=manual_same_song;
  end
 end
end
playback_sequence #(.INDEX_WIDTH(4)) u_playback_sequence(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),.mode_next(user_mode_next),
 .eof((wav_control_state==WAV_GAP && wav_restart_cnt==0 && !manual_eof_cancel)||library_load_failed),
 .manual_start(accepted_manual),.paused(playback_paused),
 .route_ready(resume_ready&&library_sequence_ready&&!library_nav_busy&&!library_nav_done&&!ctrl_transition_req&&
              !user_next&&!user_previous&&!key2_dbl_pulse&&!key1_nav_confirm),
 .playable(library_playable),.current(library_current_track),.mode(play_mode),
 .advance(sequence_advance),.target(sequence_target),.replay(sequence_replay),.stopped(playlist_stopped)
);
reg [1:0] mode_pix1,mode_pix2;
reg stopped_pix1,stopped_pix2;
always @(posedge video_clk or posedge video_rst) begin
 if(video_rst) begin mode_pix1<=0;mode_pix2<=0;stopped_pix1<=0;stopped_pix2<=0;end
 else begin
  mode_pix1<=play_mode;mode_pix2<=mode_pix1;
  stopped_pix1<=playlist_stopped;stopped_pix2<=stopped_pix1;
 end
end
reg song_available_pix1,song_available_pix2;
always @(posedge video_clk or posedge video_rst) begin
 if(video_rst) begin song_available_pix1<=0;song_available_pix2<=0;end
 else begin song_available_pix1<=song_valid[active_idx_sd2];song_available_pix2<=song_available_pix1;end
end
reg [2:0] bass_pix1,bass_pix2,mid_pix1,mid_pix2,treble_pix1,treble_pix2;
reg [3:0] edit_pix1,edit_pix2;
checkpoint_snapshot_cdc #(.WIDTH(5)) u_lyric_settings_cdc(
 .src_clk(sd_card_clk),.src_rst_n(sdcard_rst_n),.dst_clk(video_clk),.dst_rst_n(video_rst_n),
 .source_bundle({lyric_alpha_sd^2'd1,lyric_position_sd^3'd7}),.destination_bundle(lyric_settings_bundle)
);
assign lyric_alpha_p2=lyric_settings_bundle[4:3]^2'd1;
assign lyric_position_p2=lyric_settings_bundle[2:0]^3'd7;
always @(posedge video_clk or posedge video_rst) begin
 if(video_rst) begin
  bass_pix1<=2;bass_pix2<=2;mid_pix1<=2;mid_pix2<=2;
  treble_pix1<=2;treble_pix2<=2;edit_pix1<=0;edit_pix2<=0;
 end else begin
  bass_pix1<=eq_bass;bass_pix2<=bass_pix1;
  mid_pix1<=eq_mid;mid_pix2<=mid_pix1;
  treble_pix1<=eq_treble;treble_pix2<=treble_pix1;
  edit_pix1<=eq_edit_target;edit_pix2<=edit_pix1;
 end
end
reg pause_pix1,pause_pix2;
reg volume_mode_pix1,volume_mode_pix2;
reg [4:0] volume_pix1,volume_pix2;
always @(posedge video_clk or posedge video_rst) begin
 if(video_rst) begin pause_pix1<=0;pause_pix2<=0;volume_pix1<=16;volume_pix2<=16;volume_mode_pix1<=0;volume_mode_pix2<=0;end
 else begin
  pause_pix1<=playback_paused;pause_pix2<=pause_pix1;
  volume_pix1<=user_volume;volume_pix2<=volume_pix1;
  volume_mode_pix1<=volume_mode_sd;volume_mode_pix2<=volume_mode_pix1;
 end
end

// ===================== 第15课：thumbnail_controller + 转场路由 =====================
// frame_start_raw同步到sd域（40ns视频脉冲，100MHz下约4拍宽，边沿检测可靠）
always @(posedge sd_card_clk or posedge sdcard_rst) begin
    if (sdcard_rst) begin
        fs_sd1 <= 1'b0;
        fs_sd2 <= 1'b0;
    end else begin
        fs_sd1 <= frame_start_raw;
        fs_sd2 <= fs_sd1;
    end
end

library_browser_controller u_thumb_ctrl (
    .clk(sd_card_clk),.rst_n(sdcard_rst_n),
    .key_right(key1_nav_right),.key_left(key2_nav_left),
    .key_confirm(key1_nav_confirm),.key_mode(key2_dbl_pulse),
    .frame_start(fs_sd1 && !fs_sd2),.busy(transition_busy||library_route_busy),.ready(sd_free),
    .menu_ready(menu_ready_sd && !image_edit_sd),.playable(library_playable),.current_track(library_current_track),
    .cache_page(library_cache_page),.view_mode(ctrl_view_mode),.focus_track(ctrl_focus_track),
    .transition_select(ctrl_transition_select),.transition_req(ctrl_transition_req)
);

// 转场触发源与全黑时刻路由：
// 触发 = KEY1下一张（仅全屏，缩略图下KEY1是导航键）| controller的transition_req；
// 全黑时刻：有sel_pending → u_control.select_event(sel_index)（快速选择）；
//          同时应用ctrl_view_mode到thumb_mode_sd（黑屏盖住切换）；
//          无pending → 原样放行给u_control.next_event（第10课下一张语义不变）。
// 【勿删】模式切换也要补一次"同图select"——fade的S_HOLD只认index_commit退出
// （第10课假设每次转场必切图），纯模式切换不补提交会永久卡死在黑屏。
// fade_busy期间重复触发被转场控制器忽略（S_IDLE才受理），pending保持到下次全黑。
assign sel_pending=library_route_busy;
assign sel_index=library_cover_slot;
library_page_router #(.BROWSE_PAGING(1)) u_library_router(
 .clk(sd_card_clk),.rst_n(sdcard_rst_n),.catalog_playable(library_catalog_playable),
 .cache_page(library_cache_page),.cache_complete(loader_image_complete & song_valid),
 .cache_ready(sd_free),.cache_done(library_page_done),
 .manual_request(resume_route_request || (resume_ready && manual_track_request)),
 .manual_found(resume_route_request || manual_found),.manual_target(resume_route_request ? resume_route_target : manual_target),
 .auto_request(resume_ready && sequence_advance),.auto_target(sequence_target),
 .view_request(resume_ready && ctrl_transition_req),.view_select(ctrl_transition_select),.target_view(ctrl_view_mode),
 .focus_slot(ctrl_focus_index),.focus_page(ctrl_focus_track[3:2]),.fade_busy(transition_busy),.fade_black(fade_next_event),
 .control_busy(library_control_busy),.route_busy(library_route_busy),.sequence_ready(library_sequence_ready),
 .playable(library_playable),.current_track(library_current_track),.pending_track(library_pending_track),
 .audio_allowed(library_audio_allowed),.thumbnail(thumb_mode_sd),
 .fade_request(library_fade_request),.cover_select(library_cover_select),.cover_slot(library_cover_slot),
 .page_start(library_page_start),.target_page(library_target_page),
 .manual_accepted(accepted_manual),.manual_same(manual_same_song),
 .load_failed(library_load_failed),.abort_toggle(library_abort_toggle),
 .keep_valid(library_keep_valid),.keep_slot(library_keep_slot)
);

// 模式/四图完成位/参数档位跨域到video_clk（准静态，两级同步）
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        thumb_mode_pix1 <= 1'b0;
        menu_ready_pix1<=0;menu_ready_pix2<=0;
        browser_focus_pix1<=0;browser_focus_pix2<=0;
        browse_valid_pix1<=0;browse_valid_pix2<=0;
        thumb_mode_pix2 <= 1'b0;
        imgc_pix1       <= 4'd0;
        imgc_pix2       <= 4'd0;
        res_width_pix1  <= 0;res_width_pix2  <= 0;
        res_height_pix1 <= 0;res_height_pix2 <= 0;
        res_valid_pix1  <= 0;res_valid_pix2  <= 0;
        bright_lvl_pix1 <= 3'd0;
        bright_lvl_pix2 <= 3'd0;
        contr_lvl_pix1  <= 3'd0;
        contr_lvl_pix2  <= 3'd0;
    end else begin
        thumb_mode_pix1 <= thumb_mode_sd;
        menu_ready_pix1<=menu_ready_sd;menu_ready_pix2<=menu_ready_pix1;
        browser_focus_pix1<=ctrl_focus_track;browser_focus_pix2<=browser_focus_pix1;
        browse_valid_pix1<=library_playable;browse_valid_pix2<=browse_valid_pix1;
        thumb_mode_pix2 <= thumb_mode_pix1;
        imgc_pix1       <= loader_image_complete;
        imgc_pix2       <= imgc_pix1;
        res_width_pix1  <= bmp_meta_width_bcd;
        res_width_pix2  <= res_width_pix1;
        res_height_pix1 <= bmp_meta_height_bcd;
        res_height_pix2 <= res_height_pix1;
        res_valid_pix1  <= bmp_meta_valid;
        res_valid_pix2  <= res_valid_pix1;
        bright_lvl_pix1 <= bright_level;
        bright_lvl_pix2 <= bright_lvl_pix1;
        contr_lvl_pix1  <= contr_level;
        contr_lvl_pix2  <= contr_lvl_pix1;
        focus_idx_pix1  <= ctrl_focus_index;   // 第15课：焦点跨域（准静态）
        focus_idx_pix2  <= focus_idx_pix1;
    end
end

// Resolution metadata follows the bank selected after the frame-boundary commit.
// Delaying the latch by one pixel clock avoids sampling the pre-commit index.
always @(posedge video_clk or posedge video_rst) begin
    if(video_rst) begin
        frame_start_meta<=0;resolution_valid_frame<=0;
        resolution_width_frame<=0;resolution_height_frame<=0;
    end else begin
        frame_start_meta<=frame_start_raw;
        if(frame_start_meta) begin
            resolution_valid_frame<=res_valid_pix2[active_index_pix];
            case(active_index_pix)
                0: begin resolution_width_frame<=res_width_pix2[15:0];resolution_height_frame<=res_height_pix2[15:0];end
                1: begin resolution_width_frame<=res_width_pix2[31:16];resolution_height_frame<=res_height_pix2[31:16];end
                2: begin resolution_width_frame<=res_width_pix2[47:32];resolution_height_frame<=res_height_pix2[47:32];end
                default: begin resolution_width_frame<=res_width_pix2[63:48];resolution_height_frame<=res_height_pix2[63:48];end
            endcase
        end
    end
end

always @(posedge video_clk or posedge video_rst) begin
    if(video_rst) begin
        transition_pref_pix1<=0;transition_pref_pix2<=0;
        clean_pix1<=0;clean_pix2<=0;
        image_edit_pix1<=0;image_edit_pix2<=0;
    end else begin
        transition_pref_pix1<=transition_pref_sd;transition_pref_pix2<=transition_pref_pix1;
        clean_pix1<=clean_mode_sd;clean_pix2<=clean_pix1;
        image_edit_pix1<=image_edit_sd;image_edit_pix2<=image_edit_pix1;
    end
end

always @(posedge video_clk or posedge video_rst) begin
    if(video_rst) begin clean_frame<=0;transition_text_q<=0;end
    else begin
        if(!fade_active&&!wipe_active) transition_text_q<=0;
        if(frame_start_raw) begin
            clean_frame<=clean_pix2;
            if(wipe_active) transition_text_q<=2;
            else if(fade_active) transition_text_q<=1;
            else transition_text_q<=0;
        end
    end
end

// 第15课：焦点帧边界锁存（黄框切换不撕裂，与bright_q同机制）
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        focus_idx_q <= 2'd0;browser_focus_q<=0;browse_valid_q<=0;
    end else if (frame_start_raw) begin
        focus_idx_q <= browser_focus_pix2[1:0];browser_focus_q<=browser_focus_pix2;browse_valid_q<=browse_valid_pix2;
    end
end

// ===================== 第14课：参数档位LUT + 帧边界锁存 =====================
// 档位LUT用case函数（课件综合陷阱：initial-ROM在安路TD综合后无驱动HDL-5314）
function [7:0] bright_val;
    input [2:0] lvl;
    begin
        case (lvl)
            3'd0:    bright_val = 8'd255;
            3'd1:    bright_val = 8'd192;
            3'd2:    bright_val = 8'd128;
            3'd3:    bright_val = 8'd64;
            default: bright_val = 8'd32;
        endcase
    end
endfunction
function [7:0] contr_val;
    input [2:0] lvl;
    begin
        case (lvl)
            3'd0:    contr_val = 8'd128;
            3'd1:    contr_val = 8'd160;
            3'd2:    contr_val = 8'd192;
            3'd3:    contr_val = 8'd255;
            default: contr_val = 8'd64;
        endcase
    end
endfunction
function [11:0] bright_bcd;
    input [2:0] lvl;
    begin
        case (lvl)
            3'd0:    bright_bcd = 12'h255;
            3'd1:    bright_bcd = 12'h192;
            3'd2:    bright_bcd = 12'h128;
            3'd3:    bright_bcd = 12'h064;
            default: bright_bcd = 12'h032;
        endcase
    end
endfunction
function [11:0] contr_bcd;
    input [2:0] lvl;
    begin
        case (lvl)
            3'd0:    contr_bcd = 12'h128;
            3'd1:    contr_bcd = 12'h160;
            3'd2:    contr_bcd = 12'h192;
            3'd3:    contr_bcd = 12'h255;
            default: contr_bcd = 12'h064;
        endcase
    end
endfunction

// 参数帧边界生效：帧起始才锁存，一帧内不变（画面不跳变/无半帧分界线）
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        bright_q     <= 8'd255;
        contr_q      <= 8'd128;
        bright_bcd_q <= 12'h255;
        contr_bcd_q  <= 12'h128;
    end else if (frame_start_raw) begin
        bright_q     <= bright_val(bright_lvl_pix2);
        contr_q      <= contr_val(contr_lvl_pix2);
        bright_bcd_q <= bright_bcd(bright_lvl_pix2);
        contr_bcd_q  <= contr_bcd(contr_lvl_pix2);
    end
end

// 缩略图布局映射（课件原样）：thumb_de/focus_border供显示mux；
// source_index/x/y悬空——本工程reader顺序流架构，地址序列在reader内部生成
thumbnail_layout #(
    .DISPLAY_WIDTH(640), .DISPLAY_HEIGHT(480),
    .THUMB_WIDTH(160),   .THUMB_HEIGHT(120)
) u_thumbnail_layout (
    .in_de          (raw_de),
    .pixel_x        (raw_x),
    .pixel_y        (raw_y),
    .focus_index    (focus_idx_q),   // 第15课：焦点来自thumbnail_controller（帧边界锁存）
    .image_complete (browse_page_valid),
    .thumb_de       (thumb_de),
    .source_index   (),
    .source_x       (),
    .source_y       (),
    .focus_border   (thumb_focus_border)
);

// 消费门控：缩略图模式只消费左上320x240区域（reader序列严格按此光栅顺序供数）；
// 门控不带image_complete（未加载bank的字照常消费、显示黑），保证每帧恰好76800字
assign thumb_region  = (raw_x < 12'd320) && (raw_y < 12'd240);
assign pixel_consume = raw_de && player_enable_pix &&
                       (!thumb_mode_frame || thumb_region);

// 像素选择：全屏=原逻辑；缩略图=焦点黄框 > 格内图 > 黑（模式为reader帧边界生效版，不撕裂）
assign selected_rgb = !player_enable_pix ? 24'h000000 :
                      thumb_mode_frame   ? (thumb_focus_border ? 24'hFFE000 :
                                            (thumb_de && reader_pixel_valid) ? reader_rgb :
                                            24'h000000) :
                      (reader_pixel_valid ? reader_rgb : 24'h000000);

// ===================== 第10课新增：像素级转场（alpha乘法 + Wipe选择） =====================
// 纯组合同拍实现：adapter统一寄存de/rgb，本段不引入流水线错拍；
// alpha乘法取积的高8位（=×alpha/256，近似/255；alpha=255时最大亮度254，人眼不可辨）
assign fade_mult_r = selected_rgb[23:16] * fade_alpha;
assign fade_mult_g = selected_rgb[15:8] * fade_alpha;
assign fade_mult_b = selected_rgb[7:0] * fade_alpha;
assign faded_rgb   = {fade_mult_r[15:8], fade_mult_g[15:8], fade_mult_b[15:8]};

// Wipe揭示：边界=ramp×(640/16)=ramp×40像素，左边界内显示新图，右侧未揭示区填黑
// （自动轮播切换后旧帧已不在读流中，单读端口无法新旧两图同显，故从黑揭示）
assign wipe_boundary  = wipe_ramp * 10'd40;
assign transition_rgb = wipe_active ?
                        ((raw_x[9:0] < wipe_boundary) ? selected_rgb : 24'h000000) :
                        faded_rgb;

// ===================== 第14课新增：亮度/对比度调节（转场之后、OSD之前） =====================
// 纯组合（无打拍，链路与raw_de/raw_x对齐）；亮度255/对比度128=逐位直通（回归基准）
brightness_contrast_adjust u_bc_adjust (
    .rgb_in     (transition_rgb),
    .brightness (bright_q),
    .contrast   (contr_q),
    .rgb_out    (adj_rgb)
);

// ===================== 第9课新增：OSD状态叠加（亮度对比度之后、adapter之前） =====================
// 屏幕左上角(8,8)渲染4字符：图片编号1-4 / A自动 E手动 / 错误码两位hex；无错黄色、有错红色
// de取未门控的raw_de：内部line_y永远跟随真实视频行，player使能切换瞬间也不会错行；
// HDMI始终发送完整有效区；首图未就绪时底图为黑，OSD仍可显示加载错误。
osd_overlay_24 #(
    .OSD_X(8),    // OSD左上角X=8
    .OSD_Y(8)     // OSD左上角Y=8
) u_osd_overlay (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (raw_vs),
    .de           (raw_de),
    .rgb_in       (adj_rgb),              // 第14课：先亮度对比度调节再叠OSD
    .pixel_x      (raw_x[9:0]),
    .active_index (active_index_pix),
    .auto_enabled (auto_en_pix2),
    .error_code   (media_err_pix2),
    .rgb_out      (osd_rgb_out),
    .de_out       (osd_de_out),
    .osd_active   (osd_active)
);

// ===================== 第14课新增：参数OSD第二行（OSD之后、频谱之前） =====================
// (8,20)渲染"B255 C128"淡蓝参数行；独立模块叠加，不动第9课OSD文件
param_osd_overlay #(
    .OSD_X(8), .OSD_Y(20)
) u_param_osd (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (raw_vs),
    .de           (raw_de),
    .rgb_in       (osd_rgb_out),
    .pixel_x      (raw_x[9:0]),
    .bright_bcd   (bright_bcd_q),
    .contr_bcd    (contr_bcd_q),
    .paused       (pause_pix2),
    .volume       (volume_pix2),
    .volume_mode  (volume_mode_pix2),
    .bass         (bass_pix2),.mid(mid_pix2),.treble(treble_pix2),
    .edit_target  (edit_pix2[3]?3'd0:edit_pix2[2:0]),.clipped(eq_clipped),
    .play_mode    (mode_pix2),
    .stopped      (stopped_pix2),
    .rgb_out      (param_rgb_out),
    .osd_active   ()
);

// Real BMP source dimensions for the current full-screen image.  The clean
// mode bypass below also covers this overlay; browser/MENU modes suppress it.
resolution_osd_overlay u_resolution_osd (
    .de              (raw_de),
    .pixel_x         (raw_x[9:0]),
    .pixel_y         (raw_y[9:0]),
    .show            (player_enable_pix && resolution_valid_frame &&
                      !thumb_mode_frame && !menu_mode_frame),
    .source_width_bcd(resolution_width_frame),
    .source_height_bcd(resolution_height_frame),
    .rgb_in          (param_rgb_out),
    .rgb_out         (resolution_rgb_out),
    .osd_active      ()
);

// ===================== 第12课：柱形音频频谱（OSD之后、adapter之前） =====================
// 64段胶囊柱彩虹频谱（Goertzel 120Hz~16.8kHz）：4px细柱全屏宽、中线上下对称生长、
// 每柱独立色相平滑彩虹、圆角端头、背景全透传（v3.4去黑色背景）+1px暗青中线轴，替换原波形显示
// de/vsync接未门控raw_de/raw_vs（line_y靠de下降沿重建）；采集最终PCM输出，
// WAV和提示音均参与频谱。画面启用时保留中线和最小柱，避免WAV状态隐藏频谱。
promax_audio_spectrum #(
    .WAVE_X(0), .WAVE_Y(400), .WAVE_WIDTH(640), .WAVE_HEIGHT(64)
) u_audio_spectrum (
    .clk           (video_clk),
    .rst_n         (video_rst_n),
    .vsync         (raw_vs),
    .de            (raw_de),
    .rgb_in        (resolution_rgb_out),   // 参数行和真实分辨率OSD后再叠频谱
    .pixel_x       (raw_x[9:0]),
    .enable        (player_enable_pix && !clean_frame), // 纯净模式隐藏频谱并暂停其显示更新
    .pcm_tap_valid (pcm_valid),            // 跟随实际输出音频，含WAV和提示音
    .pcm_tap_left  (pcm_left),
    .rgb_out       (wave_rgb_out),
    .spectrum_active(wave_active)
);

// Absolute source-frame position supports both forward and backward jumps.
assign wav_position=wav_origin_pix+wav_sample_cnt;
audio_position_clock u_position_clock(
 .clk(video_clk),.rst_n(video_rst_n),.sample_position(wav_position),.centiseconds(lyric_cs)
);

// ===================== 第16课：歌词叠加（频谱之后、adapter之前） =====================
// Card-loaded three-line scrolling lyrics, word-safe rows and timed highlighting.
// The lyric panel ends before spectrum y400; title and zoom path are retained.
// 纯净模式仅旁路RGB；de仍沿原链传递到HDMI adapter。
assign lyric_input_rgb=clean_frame?adj_rgb:wave_rgb_out;
scrolling_lyric_overlay #(
    .LYRIC_Y(344), .H_ACT(640),
    .CUE_BITS(8),.TEXT_BITS(12),.CUE_STORAGE(160),.TEXT_DEPTH(3072)
) u_lyric (
    .clk           (video_clk),
    .rst_n         (video_rst_n),
    .vsync         (raw_vs),
    .de            (raw_de),
    .rgb_in        (lyric_input_rgb),        // 纯净模式旁路诊断/参数/频谱
    .pixel_x       (raw_x[9:0]),
    .enable        (wav_active_pix2),
    .play_cs       (lyric_cs),
    .panel_alpha(lyric_alpha_p2),.panel_position(lyric_position_p2),
    .sd_clk        (sd_card_clk),
    .ready_sd      (lyric_visible_export),
    .timing_ready_sd(lyric_timing_ready),.timing_read_addr(lyric_timing_addr),
    .timing_read_data(lyric_timing_data),
    .cue_count_sd  (live_cue_count),
    .cue_we        (live_cue_we),
    .cue_index     (live_cue_index),
    .cue_start     (live_cue_start),
    .cue_base      (live_cue_base),
    .cue_len       (live_cue_len),
    .text_we       (live_text_we),
    .text_addr     (live_text_addr),
    .text_data     (live_text_data),
    .font_we       (live_font_we),
    .font_addr     (live_font_addr),
    .font_data     (live_font_data),
    .title_we      (live_title_we),
    .title_addr    (live_title_addr),
    .title_data    (live_title_data),
    .title_count_sd(live_title_count),
    .title_ready_sd(lyric_visible_export),
    .rgb_out       (lyric_rgb_out),
    .lyric_active  ()
);

playback_status_overlay #(.INDEX_WIDTH(4)) u_playback_status (
    .clk(video_clk),.rst_n(video_rst_n),.vsync(raw_vs),.de(raw_de),
    .pixel_x(raw_x[9:0]),.pixel_y(raw_y[9:0]),.rgb_in(lyric_rgb_out),
    .sample_count(wav_position),.total_frames(ui_total_frames),
    .song_index(library_track_pix),.stream_active(wav_active_pix2),
    .wav_stream_end(wav_stream_end),.paused(pause_pix2),.stopped(stopped_pix2),
    .play_mode(mode_pix2),.show_text(!clean_frame),.transition_active(transition_text_q),
    .rgb_out(player_ui_rgb),.osd_active()
);

library_browser_overlay u_browser_overlay(
 .enable(thumb_mode_frame),.de(raw_de),.menu_ready(menu_mode_frame),.menu_card(menu_ready_pix2),
 .paused(pause_pix2),.stopped(stopped_pix2),.pixel_x(raw_x[9:0]),.pixel_y(raw_y[9:0]),
 .page(menu_mode_frame?menu_page_frame:library_track_pix[3:2]),
 .focus_track(browser_focus_q),.playing_track(library_track_pix),
 .rgb_in(player_ui_rgb),.clean_rgb(adj_rgb),.rgb_out(browser_ui_rgb)
);

adjust_bar_overlay u_adjust_bar(
 .clk(video_clk),.rst_n(video_rst_n),.frame_start(frame_start_raw),
 .de(raw_de),.clean_mode(clean_frame),.thumbnail(thumb_mode_frame),
 .transition_pref(transition_pref_pix2),.pixel_x(raw_x[9:0]),.pixel_y(raw_y[9:0]),
 .volume(volume_pix2),.bass(bass_pix2),.mid(mid_pix2),.treble(treble_pix2),
 .brightness(bright_lvl_pix2),.contrast(contr_lvl_pix2),.edit_target(edit_pix2),
 .lyric_alpha(lyric_alpha_p2),.lyric_position(lyric_position_p2),
 .rgb_in(browser_ui_rgb),.rgb_out(presentation_rgb),.osd_active()
);


// ===================== 第8课新增：rgb_video_adapter（替换video_delay） =====================
rgb_video_adapter #(
    .HS_IN_ACTIVE_LOW(1), .VS_IN_ACTIVE_LOW(1),
    .HS_OUT_ACTIVE_LOW(1), .VS_OUT_ACTIVE_LOW(1)
) u_video_adapter (
    .pclk      (video_clk),
    .rst_n     (video_rst_n),
    .hs_in     (raw_hs),
    .vs_in     (raw_vs),
    .de_in     (osd_de_out),                       // 图片未就绪也保持视频与诊断OSD
    .rgb_in    (presentation_rgb),                  // 歌词/歌名之后叠加播放状态、歌单与调节条
    .video_clk (),
    .video_hs  (hs),
    .video_vs  (vs),
    .video_de  (de),
    .video_rgb (vout_data)
);

// ===================== SDRAM控制器信号名映射（加密IP不变） =====================
// 写端口：loader → 写CDC → sdram
assign App_wr_en   = cdc_wr_en;
assign App_wr_addr = cdc_wr_addr;
assign App_wr_din  = cdc_wr_data;
assign App_wr_dm   = cdc_wr_mask;
// 读端口：reader → sdram
assign App_rd_en   = reader_rd_en;
assign App_rd_addr = reader_rd_addr;
// sdram → reader：Sdr_rd_en/Sdr_rd_dout 在读端口例化处直接映射

sdram_refresh_guard u_refresh_guard (
    .clk(ext_mem_clk), .rst_n(mem_rst_n), .init_done(Sdr_init_done),
    .rd_active(reader_rd_burst_active), .wr_active(cdc_wr_burst_active),
    .app_rd_en(App_rd_en), .app_wr_en(App_wr_en),
    .refresh_active(Sdr_init_ref_vld), .hold_new_bursts(refresh_hold),
    .app_ref_req(refresh_request), .fault(refresh_fault_mem)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (mem_rst),
    .App_ref_req       (refresh_request),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 数码管：错误码汇聚 + 当前图片编号 =====================
// reader错误/下溢/当前图片编号跨域到sd_card_clk（准静态调试量，两级触发器）
always @(posedge sd_card_clk or posedge sdcard_rst) begin
    if (sdcard_rst) begin
        reader_error_sd1 <= 8'd0;
        refresh_fault_sd1 <= 0; refresh_fault_sd2 <= 0;
        reader_error_sd2 <= 8'd0;
        underflow_sd1    <= 1'b0;
        underflow_sd2    <= 1'b0;
        active_idx_sd1   <= 2'd0;
        active_idx_sd2   <= 2'd0;
    end else begin
        reader_error_sd1 <= reader_error;
        refresh_fault_sd1 <= refresh_fault_mem; refresh_fault_sd2 <= refresh_fault_sd1;
        reader_error_sd2 <= reader_error_sd1;
        underflow_sd1    <= reader_underflow;
        underflow_sd2    <= underflow_sd1;
        active_idx_sd1   <= active_index_pix;
        active_idx_sd2   <= active_idx_sd1;
    end
end

// 错误码优先级：loader 0x4x / 控制器 0x5x / reader 0x6x（underflow合并为0x63），数码管显示高半字节
assign media_err = refresh_fault_sd2            ? 8'h47               :
                   (reader_error_sd2 != 8'd0)    ? reader_error_sd2    :
                   underflow_sd2                 ? 8'h63               :
                   (loader_memory_error != 8'd0) ? loader_memory_error :
                                                   control_error;
// Decimal global track number 1..16, with the original error-code priority.
wire [4:0] displayed_song_number={1'b0,library_current_track}+5'd1;
wire display_has_error=(bmp_err_code!=0)||(media_err!=0);
wire [3:0] displayed_song_ones=displayed_song_number>=10 ?
    displayed_song_number-5'd10:displayed_song_number[3:0];
assign state_code = (bmp_err_code != 4'd0) ? bmp_err_code :
                    (media_err != 8'd0)    ? media_err[7:4] :
                                             displayed_song_ones;

wire [6:0] seg_tens_data=(!display_has_error&&displayed_song_number>=10)?
    7'b111_1001:7'b111_1111;
reg [13:0] seg_digits_s1,seg_digits_s2;
always @(posedge clk or negedge sys_rst_n)begin
    if(!sys_rst_n)begin seg_digits_s1<=14'h3fff;seg_digits_s2<=14'h3fff;end
    else begin
        seg_digits_s1<={seg_tens_data,seg_data_0};
        seg_digits_s2<=seg_digits_s1;
    end
end

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (sys_rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,seg_digits_s2[13:7]}),
    .seg_data_5        ({1'b1,seg_digits_s2[6:0]})
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (video_rst),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (video_rst),
    .O_pulse (edid_trig)
);

// ===================== 音频链路（像素时钟驱动，无需独立音频PLL） =====================
assign rst_n_video = video_rst_n;   // 第5课：改用video_clk域同步释放复位

// 图片编号也是歌曲编号。视频域的active_index经过两级同步后才启动对应
// SONG1..4.WAV；切歌时先停文件流，等当前扇区结束再启动新文件。
runtime_lyric_manager #(.LIBRARY_MODE(1),.CUE_BITS(8),.TEXT_BITS(12),
    .MAX_CUES(158),.MAX_TEXT(3072),.KARAOKE(1),.FONT_RANGE_READ(1)) u_runtime_lyrics (
    .clk(sd_card_clk), .rst_n(sdcard_rst_n), .sd_free(sd_free && library_audio_allowed),
    .timing_clk(video_clk),.timing_read_addr(lyric_timing_addr),
    .timing_read_data(lyric_timing_data),.timing_ready(lyric_timing_ready),
    .active_song(active_idx_sd2),.font_bank({library_cache_page,active_idx_sd2}),
    .wav_play_en(wav_play_en), .wav_file_busy(wav_file_busy),
    .wav_sector_busy(wav_sector_busy),
    .lrc_valid(lrc_valid),
    .lrc0_cluster(lrc_cluster0),.lrc1_cluster(lrc_cluster1),
    .lrc2_cluster(lrc_cluster2),.lrc3_cluster(lrc_cluster3),
    .lrc0_size(lrc_size0),.lrc1_size(lrc_size1),
    .lrc2_size(lrc_size2),.lrc3_size(lrc_size3),
    .font_valid(font_valid),.font_cluster(font_cluster),.font_size(font_size),
    .ready_for_song(lyric_ready_for_song),.lyric_visible(lyric_visible),
    .sector_mode(lyric_sector_mode),.file_start(lyric_file_start),
    .file_cluster(lyric_first_cluster),.file_size(lyric_file_size),
    .file_start_offset(lyric_start_offset),.file_partial(lyric_file_partial),
    .file_done(lyric_file_done),.file_valid(lyric_file_valid),
    .file_byte(lyric_file_byte),.file_offset(lyric_file_offset),
    .file_error(lyric_file_error),
    .cue_count(live_cue_count),.cue_we(live_cue_we),
    .cue_index(live_cue_index),.cue_start(live_cue_start),
    .cue_base(live_cue_base),.cue_len(live_cue_len),
    .text_we(live_text_we),.text_addr(live_text_addr),
    .text_data(live_text_data),.font_we(live_font_we),
    .font_addr(live_font_addr),.font_data(live_font_data),
    .title_we(live_title_we),.title_addr(live_title_addr),
    .title_data(live_title_data),.title_count(live_title_count)
);


always @(posedge sd_card_clk or posedge sdcard_rst) begin
    if (sdcard_rst) begin
        wav_play_en     <= 1'b0;
        lyric_ready_q <= 0;
        wav_restart_cnt <= 27'd0;
        wav_file_start  <= 1'b0;
        selected_song   <= 2'd0;
        wav_control_state <= WAV_WAIT;
        wav_end_sd1 <= 1'b0;
        wav_end_sd2 <= 1'b0;
        wav_origin_sd<=0;wav_start_offset<=0;wav_seek_restart<=0;seek_target<=0;seek_plus<=0;
        seek_under<=0;seek_hi_gt<=0;seek_hi_eq<=0;seek_lo_ge<=0;seek_back_q<=0;seek_calc<=0;
    end else begin
        wav_file_start <= 1'b0;
        lyric_ready_q <= wav_control_state==WAV_STOP && sd_free && library_audio_allowed && lyric_ready_for_song;
        wav_end_sd1 <= wav_stream_end;
        wav_end_sd2 <= wav_end_sd1;
        if (!sd_free || !library_audio_allowed || resume_hold_audio) begin
        wav_origin_sd<=0;wav_start_offset<=0;wav_seek_restart<=0;
        wav_play_en     <= 1'b0;
        wav_restart_cnt <= 27'd0;
            wav_control_state <= WAV_WAIT;
        end else case (wav_control_state)
            WAV_WAIT: begin
                wav_origin_sd<=0;wav_start_offset<=0;wav_seek_restart<=0;
                wav_play_en <= 1'b0;
                if (song_valid[active_idx_sd2]) begin
                    selected_song <= active_idx_sd2;
                    wav_control_state <= WAV_STOP;
                end
            end
            WAV_STOP: begin
                wav_origin_sd<=0;wav_start_offset<=0;wav_seek_restart<=0;
                wav_play_en <= 1'b0;
                if (active_idx_sd2 != selected_song || !song_valid[selected_song])
                    wav_control_state <= WAV_WAIT;
                else if (lyric_ready_q && !wav_sector_busy && (!resume_apply || resume_position_ready))begin
                    if(resume_position_ok)begin
                        wav_origin_sd<=checkpoint_restore_frame;
                        wav_start_offset<=resume_start_offset;
                        // Recovery opens a new playback session: clear manual EOF/replay flags.
                        wav_seek_restart<=0;
                    end
                    wav_control_state <= WAV_START;
                end
            end
            WAV_START: begin
                wav_play_en <= 1'b1;
                wav_file_start <= 1'b1;
                wav_control_state <= WAV_RUN;
            end
            WAV_RUN: begin
                if (active_idx_sd2 != selected_song || !song_valid[selected_song]) begin
                    wav_play_en <= 1'b0;
                    wav_control_state <= WAV_WAIT;
                end else if (wav_format_error) begin
                    wav_play_en <= 1'b0;
                    wav_restart_cnt <= 27'd64_000_000;
                    wav_control_state <= WAV_GAP;
                end else if ((user_seek_back||user_seek_forward) && !transition_busy && !sel_pending &&
                             !accepted_manual && !manual_replay_pending && seek_stream_ready) begin
                    seek_back_q<=user_seek_back;seek_calc<=0;
                    wav_control_state<=WAV_SEEK_FADE;
                end else if (wav_end_sd2 || (manual_replay_pending && !wav_file_start)) begin
                    wav_play_en <= 1'b0;
                    wav_restart_cnt <= 27'd1024;
                    wav_control_state <= WAV_GAP;
                end
            end
            WAV_SEEK_FADE: begin
                // The video snapshot is captured at fade entry and held through
                // restart. Mute acknowledge arrives >=2 SD clocks after it is stable.
                if(seek_muted_s2)begin
                    case(seek_calc)
                     0:begin seek_target<=wav_origin_sd+seek_sample_snapshot;seek_calc<=1;end
                     1:begin
                        seek_plus<=seek_target+(seek_back_q?(32'd0-32'd480000):32'd480000);
                        seek_under<=seek_target<32'd480000;
                        seek_calc<=2;
                     end
                     2:begin
                        seek_target<=seek_back_q && seek_under?32'd0:seek_plus;
                        seek_calc<=3;
                     end
                     3:begin
                        seek_hi_gt<=seek_target[31:16]>ui_frames_sd[31:16];
                        seek_hi_eq<=seek_target[31:16]==ui_frames_sd[31:16];
                        seek_lo_ge<=seek_target[15:0]>=ui_frames_sd[15:0];
                        seek_plus<=ui_frames_sd-1'b1;seek_calc<=4;
                     end
                     4:begin
                        if(seek_hi_gt || (seek_hi_eq && seek_lo_ge))seek_target<=seek_plus;
                        seek_calc<=5;
                     end
                     default:;
                    endcase
                end
                if(active_idx_sd2!=selected_song || !song_valid[selected_song])begin
                    wav_play_en<=0;wav_control_state<=WAV_WAIT;
                end else if(seek_muted_s2 && seek_calc==5)begin
                    wav_play_en<=0;wav_restart_cnt<=1024;wav_control_state<=WAV_SEEK_STOP;
                end
            end
            WAV_SEEK_STOP: begin
                wav_play_en<=0;
                if(active_idx_sd2!=selected_song || !song_valid[selected_song])wav_control_state<=WAV_WAIT;
                else if(wav_restart_cnt!=0)wav_restart_cnt<=wav_restart_cnt-1'b1;
                else if(!wav_sector_busy)wav_control_state<=WAV_SEEK_PREP;
            end
            WAV_SEEK_PREP: begin
                wav_seek_restart<=1;
                wav_origin_sd<=seek_target;
                wav_start_offset<=44+{seek_target[29:0],2'b00};
                wav_control_state<=WAV_SEEK_START;
            end
            WAV_SEEK_START: begin
                if(active_idx_sd2!=selected_song || !song_valid[selected_song])wav_control_state<=WAV_WAIT;
                else begin wav_play_en<=1;wav_file_start<=1;wav_control_state<=WAV_RUN;end
            end
            WAV_GAP: begin
                wav_play_en <= 1'b0;
                if (active_idx_sd2 != selected_song)
                    wav_control_state <= WAV_WAIT;
                else if (wav_restart_cnt != 0)
                    wav_restart_cnt <= wav_restart_cnt - 1'b1;
                else
                    wav_control_state <= WAV_ENDED;
            end
            WAV_ENDED: begin
                wav_play_en <= 1'b0;
                if (active_idx_sd2 != selected_song)
                    wav_control_state <= WAV_WAIT;
                else if (sequence_replay || (manual_replay_pending && !transition_busy))
                    wav_control_state <= WAV_STOP;
            end
            default: wav_control_state <= WAV_WAIT;
        endcase
    end
end

assign wav_stream_active = wav_play_en && !wav_end_sd2;

// stream_active跨域到video_clk（准静态电平，两级同步，供音源mux选择）
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        wav_active_pix1 <= 1'b0;
        wav_active_pix2 <= 1'b0;
    end else begin
        wav_active_pix1 <= wav_stream_active;
        wav_active_pix2 <= wav_active_pix1;
    end
end

// ===================== 第11课新增：48kHz采样tick（与pcm_media_tone同款Bresenham） =====================
// 25MHz域产生~48kHz脉冲：累加器到 CLOCK_HZ-SAMPLE_HZ 即出拍，平均速率=48kHz
assign wav_sample_tick = (wav_tick_acc >= (25'd25_000_000 - 25'd48_000));
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst)
        wav_tick_acc <= 25'd0;
    else if (wav_sample_tick)
        wav_tick_acc <= wav_tick_acc + 25'd48_000 - 25'd25_000_000;
    else
        wav_tick_acc <= wav_tick_acc + 25'd48_000;
end

// WAV文件流读取由 sd_card_bmp 内共享流读器承担（owner=2，端口见 sd_card_bmp_m0）：
// 原 u_song_streamer（MAX_VISITED_CLUSTERS=65535, SEEK_SUPPORT=1）已与封面/歌词流读器合并。

// 2048 stereo samples (~42.7 ms) reserve BRAM for the 256-glyph font.
fat_wav_player #(.ADDR_WIDTH(11)) u_wav_player (
    .wr_clk        (sd_card_clk),
    .wr_rst_n      (sdcard_rst_n && wav_play_en),
    .file_valid    (wav_file_valid),
    .file_byte     (wav_file_byte),
    .file_byte_offset(wav_file_offset),
    .file_done     (wav_file_done),
    .file_error    (wav_file_error),
    .can_read_sector(wav_can_read_sector),
    .format_error  (wav_format_error),
    .stream_end    (wav_stream_end),
    .rd_clk        (video_clk),
    .rd_rst_n      (video_rst_n && wav_active_pix2),
    .sample_tick   (wav_sample_tick),
    .paused        (pause_pix2),
    .sample_left   (wav_left_out),
    .sample_right  (wav_right_out),
    .sample_valid  (wav_sample_valid),
    .sample_ready  (wav_sample_ready),
    .sample_counter(wav_sample_cnt),
    .underflow_count()
);

// SEEK_ELIGIBILITY_BEGIN
always @(posedge sd_card_clk or posedge sdcard_rst)begin
 if(sdcard_rst)seek_stream_ready<=0;
 else seek_stream_ready<=wav_play_en && !wav_format_error && ui_frames_sd!=0 && wav_file_offset>=44;
end

// SEEK_ELIGIBILITY_END
// ===================== 第11课新增：sync_fade_gain（音画同步音量包络） =====================
// 画面淡入淡出的alpha转成音频增益：转场时gain=alpha（画面黑=静音），空闲gain=255
// 本工程音频链就跑在像素时钟上，aud_clk=pix_clk=video_clk（模块内部2FF逻辑依然安全）
sync_fade_gain u_sync_fade_gain (
    .pix_clk     (video_clk),
    .pix_rst_n   (video_rst_n),
    .frame_start (frame_start),
    .alpha_pix   (fade_alpha),
    .fade_active (fade_active),
    .aud_clk     (video_clk),
    .aud_rst_n   (video_rst_n),
    .gain_aud    (gain_aud)
);

// 双声道独立增益，不把单声道复制到左右声道。
wire [7:0] transport_gain=gain_aud<seek_gain?gain_aud:seek_gain;
assign wav_gain_left = wav_left_out * $signed({1'b0, transport_gain});
assign wav_gain_right = wav_right_out * $signed({1'b0, transport_gain});
assign wav_left_gained  = wav_gain_left >>> 8;
assign wav_right_gained = wav_gain_right >>> 8;

// 媒体音调：16点正弦LUT，每张图一个六音符琶音，切图先播1.5kHz提示音(100ms)
// 第8课：图片编号直接取media_player_control的active_index（本就在video_clk域，无需再跨域同步）
// 第11课：音量由固定128改为增益包络折半（gain_aud[7:1]，空闲255→127≈原128防削波，转场跟随alpha）
// (2026-10-20曾尝试移除以省面积,实测综合反而+472LUT——移除破坏了打包有利结构,已还原)
pcm_media_tone #(
    .CLOCK_HZ    (25_000_000),
    .SAMPLE_HZ   (48000)
) u_pcm_media_tone (
    .clk          (video_clk),
    .rst_n        (rst_n_video),
    .media_id     (active_index_pix),
    .volume       ({1'b0, gain_aud[7:1]}),
    .sample_valid (tone_valid),
    .sample_ready (tone_ready),
    .sample_left  (tone_left),
    .sample_right (tone_right),
    .overflow     (tone_overflow),
    .blip_active  ()
);

// ===================== 第11课新增：audio_source_mux（WAV流优先，琶音兜底） =====================
// ready只路由给被选源：WAV播放中琶音FIFO暂停推进；WAV播完/未播自动切回琶音，不丢数据
audio_source_mux u_audio_source_mux (
    .clk           (video_clk),
    .rst_n         (video_rst_n),
    .wav_valid     (wav_sample_valid),
    .wav_ready     (wav_sample_ready),
    .wav_left      (wav_left_gained),
    .wav_right     (wav_right_gained),
    .wav_active    (wav_active_pix2),
    .arp_valid     (tone_valid),
    .arp_ready     (tone_ready),
    .arp_left      (tone_left),
    .arp_right     (tone_right),
    .force_arpeggio(1'b0),
    .out_valid     (mux_valid),
    .out_ready     (mux_ready),
    .out_left      (mux_left),
    .out_right     (mux_right)
);

// PCM契约适配：valid/ready握手，HDMI核无反压故pcm_ready常1
// 第11课：源由tone直连改为audio_source_mux输出
wire volume_valid;
wire signed [15:0] volume_left,volume_right;
wire eq_out_ready;
reg [1:0] eq_song_q;
reg eq_wav_q;
always @(posedge video_clk or posedge video_rst) begin
 if(video_rst) begin eq_song_q<=0;eq_wav_q<=0;end
 else begin eq_song_q<=active_index_pix;eq_wav_q<=wav_active_pix2;end
end
wire eq_clear=(eq_song_q!=active_index_pix)||(wav_active_pix2&&!eq_wav_q);
wire eq_mute=pause_pix2||stopped_pix2||(!wav_active_pix2&&song_available_pix2);
wire signed [15:0] eq_left,eq_right;
music_equalizer u_music_equalizer(
 .clk(video_clk),.rst_n(rst_n_video),.clear(eq_clear),
 .in_valid(mux_valid),.in_ready(mux_ready),
 .in_left(eq_mute?16'sd0:mux_left),.in_right(eq_mute?16'sd0:mux_right),
 .bass(bass_pix2),.mid(mid_pix2),.treble(treble_pix2),.volume(volume_pix2),
 .out_valid(volume_valid),.out_ready(eq_out_ready),
 .out_left(eq_left),.out_right(eq_right),.clipped(eq_clipped)
);
assign volume_left=eq_mute?16'sd0:eq_left;
assign volume_right=eq_mute?16'sd0:eq_right;
m06_pcm_contract_adapter u_pcm_contract_adapter (
    .clk            (video_clk),
    .rst_n          (rst_n_video),
    .source_valid   (volume_valid),
    .source_ready   (eq_out_ready),
    .source_left    (volume_left),
    .source_right   (volume_right),
    .pcm_valid      (pcm_valid),
    .pcm_ready      (1'b1),
    .pcm_left       (pcm_left),
    .pcm_right      (pcm_right),
    .contract_error (contract_error)
);

// ACR：48kHz样本选通计数，自动实测CTS（N=6144固定），接收端据此恢复音频时钟
audio_arc_calculate #(
    .ACR_N (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (video_rst),
    .I_audio_valid (pcm_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (video_rst),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (pcm_valid),
    .I_audio_left_data  ({pcm_left, 8'b0}),    // 16bit左对齐成24bit
    .I_audio_right_data ({pcm_right, 8'b0}),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (hdmi5x_rst),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
