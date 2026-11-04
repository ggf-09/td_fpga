`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// 第8课：media_frame_reader（帧读取器）
// 来源：第8课参考代码，针对本工程做一处适配：
//   新增 wr_burst_active 输入 / rd_burst_active 输出——本工程SDRAM控制器
//   （加密IP，沿用官方例程）要求读写burst互斥（旧frame_read_write靠
//   App_rd_busy/App_wr_busy互斥，写优先）。reader发起读burst前让位于写通道
//   （media_sdram_write_cdc）的写burst回放，并对外暴露读侧活动电平
//   （burst发射中 + 在飞数据未回完），供写侧让行。
// 双时钟域：mem_clk(ext_mem_clk,125M)发起burst读/接收数据写异步FIFO；
//           pix_clk(video_clk,25M)帧起始请求/像素消费/预取输出。
// 依赖：rfifo_32_32_512（工程已有IP：hdl_source/IP/afifo_32_16_256.v）
//       fifo_prefetch_2（第8课新增普通RTL）
// 第13课适配：新增 thumb_mode 输入 / thumb_mode_frame 输出——缩略图模式
//   （2x2四宫格，每格160x120=源图4:1最近邻，屏幕左上320x240区）。
//   本工程reader是顺序流架构（课件完赛工程是按source_x/y坐标读），故缩略图
//   地址序列由本模块内部生成；模式随帧请求锁存（与active_index同通道同拍），
//   帧边界生效不撕裂；pix侧每帧消费 307200→76800 切换（两者%128==0）。
// 第13课修正（行缓冲架构，勿回退为直接stride读）：
//   实测加密SDRAM IP对**非顺序读地址**不可靠——直接按stride-4/跨bank跳变
//   寻址时，同地址序列在不同burst时序下读出不同错误数据（先混图、后全白）。
//   故缩略图取数改为：每显示行从SDRAM读两段640字**连续长序列**
//   （bank跳转恰落在128字burst边界，640%128==0；与写侧V-flip行跳变同性质，
//   写侧非顺序burst边界跳转经loader验证可靠）→ 1280x32行缓冲BRAM →
//   再按显示序（左半stride-4 160字 + 右半stride-4 160字）泵入异步FIFO。
//   SDRAM侧所有读均为与全屏同性质的纯顺序128字burst；pix侧完全不变。
// -----------------------------------------------------------------------------
module media_frame_reader #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer IMAGE_WORDS = 307200,
    parameter integer FIFO_DEPTH = 512,
    parameter integer FIFO_MARGIN = 8,
    parameter integer BURST_SIZE = 128,
    parameter integer BURST_GAP_CYCLES = 12,
    parameter integer MAX_INFLIGHT_BURSTS = 2,
    parameter integer DIAG_RETURN_PATTERN = 0,
    parameter integer DIAG_SYNTH_STREAM = 0,
    parameter integer THUMB_WORDS = 76800,    // 第13课：缩略图帧字数 320*240
    parameter integer FRAME_ENABLE_CONTROL = 0, MENU_SUPPORT=0
) (
    input  wire                  mem_clk,
    input  wire                  mem_rst_n,
    input  wire                  controller_init_done,
    input  wire                  controller_busy,
    input  wire                  refresh_active,
    output reg                   app_rd_en,
    output reg  [ADDR_WIDTH-1:0] app_rd_addr,
    input  wire                  sdram_rd_valid,
    input  wire [31:0]           sdram_rd_data,

    // 第8课新增：读写burst互斥（写优先，同旧frame_read_write约定）
    input  wire                  wr_burst_active,  // 写通道burst回放中（含当拍意向）
    output wire                  rd_burst_active,  // 读burst发射中或有在飞数据

    input  wire                  pix_clk,
    input  wire                  pix_rst_n,
    input  wire                  frame_start,
    input  wire [1:0]            active_index,
    input  wire                  menu_ready,
    input  wire [1:0]            menu_page,
    output wire                 menu_mode_frame,
    output wire [1:0]           menu_page_frame,
    input  wire                  thumb_mode,       // 第13课：缩略图模式请求（任意时刻变化）
    output wire                  thumb_mode_frame, // 第13课：当前帧实际生效的模式（帧边界切换）
    input  wire                  pixel_consume,
    output wire [23:0]           pixel_rgb,
    output wire                  pixel_valid,
    output reg                   underflow,

    output reg                   reader_busy,
    output reg                   frame_read_done,
    output reg  [1:0]            reader_index,
    output reg  [7:0]            reader_error,
    input  wire                  frame_enable
);
    localparam [7:0] ERR_NONE          = 8'h00;
    wire frames_enabled = FRAME_ENABLE_CONTROL==0 || frame_enable;
    localparam [7:0] ERR_FRAME_OVERRUN = 8'h61;
    localparam [7:0] ERR_FIFO_OVERFLOW = 8'h62;
    localparam [7:0] ERR_UNDERFLOW     = 8'h63;
    localparam [7:0] ERR_SHORT_FRAME   = 8'h64;
    localparam integer FIFO_COUNT_W = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer BURST_COUNT_W =
        (BURST_SIZE < 2) ? 1 : $clog2(BURST_SIZE + 1);
    localparam integer INFLIGHT_COUNT_W =
        (MAX_INFLIGHT_BURSTS * BURST_SIZE < 2) ? 1 :
        $clog2(MAX_INFLIGHT_BURSTS * BURST_SIZE + 1);

    // 第13课修正：缩略图行缓冲参数
    // 每显示行取数 = 左bank源行640字 + 右bank源行640字（各5个128字顺序burst）
    // 全帧SDRAM读 = 240行 x 1280 = 307200（恰与IMAGE_WORDS同值，但语义不同）
    localparam [ADDR_WIDTH:0] FILL_WORDS_W = 240*1280;      // 缩略图帧SDRAM读字数
    localparam [FIFO_COUNT_W-1:0] THUMB_FEED_ROOM = 160;    // 泵入前提：FIFO余量≥320
    localparam [1:0] TS_FILL  = 2'd0;   // 行填充（burst引擎发顺序读）
    localparam [1:0] TS_FWAIT = 2'd1;   // 等FIFO腾出320字空间
    localparam [1:0] TS_FEED  = 2'd2;   // 行缓冲→异步FIFO（显示序320字）

    reg request_pending_pix;
    reg request_toggle_pix;
    reg [1:0] request_index_pix;
    reg request_menu_pix;
    reg [1:0] request_page_pix;
    reg menu_sync1_mem,menu_sync2_mem,reload_menu_mem,reader_menu_mem;
    reg [1:0] page_sync1_mem,page_sync2_mem,reload_page_mem,reader_page_mem;
    reg request_mode_pix;    // 第13课：本帧模式（随请求锁存，即thumb_mode_frame）
    reg frame_armed_pix;
    reg [ADDR_WIDTH:0] consumed_count_pix;

    reg request_sync1_mem;
    reg request_sync2_mem;
    reg request_seen_mem;
    reg [1:0] index_sync1_mem;
    reg [1:0] index_sync2_mem;
    reg mode_sync1_mem;      // 第13课：模式随索引同通道跨域
    reg mode_sync2_mem;
    reg reload_mode_mem;
    reg reader_mode_mem;     // mem域当前帧模式
    reg [7:0] t_row_mem;     // 第13课修正：缩略图显示行号0..239（FEED完成时推进）
    reg [1:0] tstate_mem;    // 行供给FSM：TS_FILL/TS_FWAIT/TS_FEED
    reg [11:0] fill_word_mem;// 本行已发SDRAM读 0..1280
    reg [10:0] buf_waddr;    // 行缓冲写指针（返回序=请求序，顺序写0..1279）
    reg [10:0] buf_raddr;    // 行缓冲读指针（FEED泵用）
    reg [9:0]  feed_rd_i;    // 本行已发起缓冲读 0..320
    reg feed_last;
    reg [8:0]  feed_wr_i;    // 本行已写入FIFO 0..319
    reg        feed_pipe_v,feed_pipe_d;
    // Registered read address plus synchronous RAM data require two valid
    // stages before FIFO write; one stage repeats the first pixel of a row.
    reg [31:0] line_buf [0:1279] /* fehdl force_ram=1, ram_style="bram" */;
    reg [31:0] line_buf_rdata;
    reg reload_pending_mem;
    reg [1:0] reload_index_mem;
    reg [2:0] fifo_reset_count_mem;
    reg [ADDR_WIDTH:0] issued_count_mem;
    reg all_issued_mem /* fehdl keep="true" */;
    reg [ADDR_WIDTH:0] returned_count_mem;
    reg [INFLIGHT_COUNT_W-1:0] inflight_count_mem;
    reg inflight_empty_mem /* fehdl keep="true" */;
    reg burst_active_mem;
    reg [BURST_COUNT_W-1:0] burst_issued_mem;
    reg [BURST_COUNT_W-1:0] burst_target_mem;
    reg [7:0] burst_gap_count_mem;
    reg [ADDR_WIDTH:0] diag_written_count_mem;
    reg [9:0] diag_column_mem;
    reg [23:0] diag_rgb_mem;
    reg [1:0] fifo_release_mem;
    reg [1:0] fifo_release_pix;

    wire fifo_reset_request = !mem_rst_n || !pix_rst_n ||
                              (fifo_reset_count_mem != 0);
    wire fifo_reset = fifo_reset_request ||
                      !fifo_release_mem[1] || !fifo_release_pix[1];
    wire fifo_full;
    wire fifo_empty;
    wire fifo_almost_full;
    wire [FIFO_COUNT_W-1:0] fifo_wrusedw;
    wire [31:0] fifo_raw_data;
    wire fifo_raw_valid;
    wire fifo_raw_read_en;
    wire prefetch_valid;
    wire [31:0] prefetch_data;
    wire pixel_pop = frames_enabled && pixel_consume && prefetch_valid;
    wire [ADDR_WIDTH:0] inflight_words =
        {{(ADDR_WIDTH+1-INFLIGHT_COUNT_W){1'b0}}, inflight_count_mem};
    localparam [ADDR_WIDTH:0] IMAGE_WORDS_W = IMAGE_WORDS;
    localparam [ADDR_WIDTH:0] THUMB_WORDS_W = THUMB_WORDS;
    // 第13课修正：SDRAM侧发射/回收目标——全屏307200，缩略图行缓冲架构同为
    // 307200（240行x1280字）；帧完成判据：全屏=末字返回，缩略图=末字泵入FIFO
    wire [ADDR_WIDTH:0] issue_target =
        reader_mode_mem ? (reader_menu_mem ? 240*640 : FILL_WORDS_W) : IMAGE_WORDS_W;

    // 第13课修正：行填充地址（全顺序：bank基址+行内偏移，bank跳变落在burst边界）
    // 显示行t_row：行对=t_row>=120（bank0/1 vs 2/3）；源行=local行*4 →
    // 行基址=bank_base({pair,0}) + local行*2560（*2560=<<11+<<9 纯移位加）
    wire       t_pair = (t_row_mem >= 8'd120);
    wire [7:0] row_local = t_pair ? (t_row_mem - 8'd120) : t_row_mem;
    wire [ADDR_WIDTH-1:0] sr_row_base =
        {{(ADDR_WIDTH-19){1'b0}}, row_local, 11'b00000000000} +   // row_local*2048
        {{(ADDR_WIDTH-17){1'b0}}, row_local, 9'b000000000};       // + row_local*512
    wire [ADDR_WIDTH-1:0] row_base_L = bank_base({t_pair, 1'b0}) + sr_row_base;
    // 行内第fill_word字：<640读左bank连续段，≥640读右bank连续段（+IMAGE_WORDS-640）
    reg [ADDR_WIDTH-1:0] source_row_q,row_left_q,row_right_q;
    reg source_pair_q;
    reg [1:0] row_base_wait;
    // Two stages isolate row/pair arithmetic from the 125-MHz issue address.
    // A row change gets a short settling interval before its first burst.
    always @(posedge mem_clk)begin
        source_row_q<=sr_row_base;source_pair_q<=t_pair;
        row_left_q<=source_row_q+(source_pair_q?IMAGE_WORDS*2:0);
        row_right_q<=source_row_q+(source_pair_q?IMAGE_WORDS*3-640:IMAGE_WORDS-640);
    end
    wire [ADDR_WIDTH-1:0] fill_addr =
        (fill_word_mem>=640?row_right_q:row_left_q)+fill_word_mem;

    // 第13课修正：FEED显示序读址——左半 stride-4（i*4），右半 stride-4（640+(i-160)*4）
    wire [9:0]  feed_right10 = feed_rd_i - 10'd160;   // 仅feed_rd_i>=160时有效
    wire [10:0] feed_addr = (feed_rd_i < 10'd160) ?
                            {1'b0, feed_rd_i[7:0], 2'b00} :
                            (11'd640 + {1'b0, feed_right10[7:0], 2'b00});
    wire [ADDR_WIDTH-1:0] menu_page_base = reader_page_mem==0?IMAGE_WORDS*4:
        reader_page_mem==1?IMAGE_WORDS*4+76800:
        reader_page_mem==2?IMAGE_WORDS*4+153600:IMAGE_WORDS*4+230400;
    wire [ADDR_WIDTH-1:0] menu_row_base = (row_local<<9)+(row_local<<7);
    reg [ADDR_WIDTH-1:0] menu_line_base_q;
    // A row advances at the end of FEED. The following FILL starts a burst
    // one clock before its first issue, giving this base register time to
    // settle. Do not combine row/page arithmetic with the 125-MHz address.
    always @(posedge mem_clk) menu_line_base_q<=menu_page_base+menu_row_base;
    wire [ADDR_WIDTH-1:0] menu_fill_addr = menu_line_base_q+fill_word_mem;
    wire [11:0] row_fill_words=reader_menu_mem?12'd640:12'd1280;
    wire [10:0] active_feed_addr=reader_menu_mem?((t_pair?11'd320:11'd0)+feed_rd_i):feed_addr;
    wire feed_we = reader_mode_mem && (tstate_mem == TS_FEED) &&
                   feed_pipe_d && !fifo_reset;

    wire final_return = returned_count_mem == issue_target - 1'b1;
    wire [ADDR_WIDTH+1:0] reserved_words =
        {{(ADDR_WIDTH+2-FIFO_COUNT_W){1'b0}}, fifo_wrusedw} +
        {{1{1'b0}}, inflight_words};
    localparam integer FULL_BURSTS_ONLY = (IMAGE_WORDS % BURST_SIZE) == 0;
    wire [ADDR_WIDTH:0] remaining_words = issue_target - issued_count_mem;
    wire [ADDR_WIDTH:0] next_burst_words =
        FULL_BURSTS_ONLY ? BURST_SIZE :
        ((remaining_words > BURST_SIZE) ? BURST_SIZE : remaining_words);
    wire [ADDR_WIDTH+2:0] reserved_after_burst =
        {{1{1'b0}}, reserved_words} + {{2{1'b0}}, next_burst_words};
    wire inflight_window_ok = (MAX_INFLIGHT_BURSTS == 1) ?
        inflight_empty_mem :
        ((inflight_words + next_burst_words) <=
         (MAX_INFLIGHT_BURSTS * BURST_SIZE));
    localparam integer RES_COUNT_W=(FIFO_COUNT_W>INFLIGHT_COUNT_W?FIFO_COUNT_W:INFLIGHT_COUNT_W)+1;
    localparam integer PIPE_RESERVATION=FULL_BURSTS_ONLY && BURST_GAP_CYCLES>=3 && FIFO_MARGIN>=4;
    reg [RES_COUNT_W-1:0] reserved_sum_q;
    // Burst gaps settle this extra stage before another reservation. The
    // FIFO margin also covers the one-word return/used-count port latency.
    wire fifo_reservation_ok = PIPE_RESERVATION ?
        reserved_sum_q <= (FIFO_DEPTH-FIFO_MARGIN-BURST_SIZE) :
        reserved_after_burst <= (FIFO_DEPTH - FIFO_MARGIN);
    reg inflight_window_ok_q;
    reg fifo_reservation_ok_q;
    localparam integer PIPE_BURST_CONTEXT=BURST_GAP_CYCLES>=3 && FIFO_MARGIN>=8;
    wire burst_context_ok=controller_init_done && row_base_wait==0 &&
        (!reader_mode_mem || ((tstate_mem==TS_FILL) && (fill_word_mem!=row_fill_words))) &&
        inflight_window_ok_q && fifo_reservation_ok_q;
    reg burst_context_ok_q;
    // Burst gaps settle this extra eligibility stage; the FIFO margin covers
    // its count latency. Keep write/refresh interlocks in the immediate path.
    always @(posedge mem_clk or negedge mem_rst_n)begin
        if(!mem_rst_n)burst_context_ok_q<=0;
        else burst_context_ok_q<=burst_context_ok;
    end
    // 第8课：读burst发起条件加“写通道不在burst”互斥项（写优先）
    // 第13课修正：缩略图模式额外要求处于行填充态且本行1280字未发完
    wire start_burst = !DIAG_SYNTH_STREAM && reader_busy &&
                       fifo_reset_count_mem == 0 && !burst_active_mem &&
                       burst_gap_count_mem == 0 &&
                       !all_issued_mem &&
                       !wr_burst_active && !refresh_active &&
                       (PIPE_BURST_CONTEXT?burst_context_ok_q:burst_context_ok);
    wire issue_allowed = !DIAG_SYNTH_STREAM && reader_busy && burst_active_mem;
    wire diag_stream_write = DIAG_SYNTH_STREAM && reader_busy &&
                             !fifo_reset && !fifo_full;
    // 第13课修正：FIFO写源二选一——全屏=SDRAM返回直写；缩略图=行缓冲泵入
    wire fifo_write_enable = DIAG_SYNTH_STREAM ? diag_stream_write :
                             reader_mode_mem ? feed_we :
                             // The FIFO gates its RAM write with !full_flag.
                             // Avoid a second full gate across the module port.
                             (sdram_rd_valid && !fifo_reset);
    wire [31:0] fifo_write_data = (DIAG_RETURN_PATTERN || DIAG_SYNTH_STREAM) ?
                                  {8'h00, diag_rgb_mem} :
                                  reader_mode_mem ? line_buf_rdata : sdram_rd_data;

    // 读侧活动电平（寄存器量，供写通道让行；burst发射中或读数据未回完都算忙）
    assign rd_burst_active = burst_active_mem || !inflight_empty_mem;

    always @* begin
        if (diag_column_mem < 10'd80)
            diag_rgb_mem = 24'hffffff;
        else if (diag_column_mem < 10'd160)
            diag_rgb_mem = 24'hffff00;
        else if (diag_column_mem < 10'd240)
            diag_rgb_mem = 24'h00ffff;
        else if (diag_column_mem < 10'd320)
            diag_rgb_mem = 24'h00ff00;
        else if (diag_column_mem < 10'd400)
            diag_rgb_mem = 24'hff00ff;
        else if (diag_column_mem < 10'd480)
            diag_rgb_mem = 24'hff0000;
        else if (diag_column_mem < 10'd560)
            diag_rgb_mem = 24'h0000ff;
        else
            diag_rgb_mem = 24'h000000;
    end

    function [ADDR_WIDTH-1:0] bank_base;
        input [1:0] index;
        begin
            case (index)
                2'd0: bank_base = {ADDR_WIDTH{1'b0}};
                2'd1: bank_base = IMAGE_WORDS;
                2'd2: bank_base = IMAGE_WORDS * 2;
                default: bank_base = IMAGE_WORDS * 3;
            endcase
        end
    endfunction

    // 请求比frame_start晚锁存一拍：media_player_control在frame_start同一拍
    // 提交active_index，本模块晚一拍采样才能拿到刚提交的新值（切换原子性）。
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            request_pending_pix <= 1'b0;
            request_toggle_pix <= 1'b0;
            request_index_pix <= 2'd0;
            request_mode_pix <= 1'b0;request_menu_pix<=0;request_page_pix<=0;
            frame_armed_pix <= 1'b0;
            consumed_count_pix <= 0;
            underflow <= 1'b0;
            fifo_release_pix <= 2'b00;
        end else begin
            if (fifo_reset_request)
                fifo_release_pix <= 2'b00;
            else
                fifo_release_pix <= {fifo_release_pix[0], 1'b1};

            if (!frames_enabled) begin
                request_pending_pix <= 0;
                frame_armed_pix <= 0;
                consumed_count_pix <= 0;
                underflow <= 0;
            end else if (frame_start) begin
                if (frame_armed_pix &&
                    consumed_count_pix != (request_mode_pix ? THUMB_WORDS_W : IMAGE_WORDS_W)) begin
                    underflow <= 1'b1;
                end
                consumed_count_pix <= 0;
                request_pending_pix <= 1'b1;
            end else if (request_pending_pix) begin
                request_index_pix <= active_index;
                request_menu_pix <= MENU_SUPPORT!=0 && menu_ready && thumb_mode;
                request_page_pix <= menu_page;
                request_mode_pix <= thumb_mode;    // 第13课：模式随帧请求锁存
                request_toggle_pix <= ~request_toggle_pix;
                request_pending_pix <= 1'b0;
                frame_armed_pix <= 1'b1;
            end

            if (frames_enabled && pixel_consume) begin
                if (prefetch_valid)
                    consumed_count_pix <= consumed_count_pix + 1'b1;
                else if (frame_armed_pix)
                    underflow <= 1'b1;
            end
        end
    end

    // 第13课修正：1280x32行缓冲（单口BRAM：填充写/泵出读分时复用，不重叠）
    always @(posedge mem_clk) begin
        if (reader_mode_mem && sdram_rd_valid && !fifo_reset)
            line_buf[buf_waddr] <= sdram_rd_data;
        line_buf_rdata <= line_buf[buf_raddr];
    end

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            request_sync1_mem <= 1'b0;
            request_sync2_mem <= 1'b0;
            request_seen_mem <= 1'b0;
            index_sync1_mem <= 2'd0;
            index_sync2_mem <= 2'd0;
            mode_sync1_mem <= 1'b0;
            menu_sync1_mem<=0;menu_sync2_mem<=0;reload_menu_mem<=0;reader_menu_mem<=0;
            page_sync1_mem<=0;page_sync2_mem<=0;reload_page_mem<=0;reader_page_mem<=0;
            mode_sync2_mem <= 1'b0;
            reload_mode_mem <= 1'b0;
            reader_mode_mem <= 1'b0;
            t_row_mem <= 8'd0;
            tstate_mem <= TS_FILL;
            fill_word_mem <= 12'd0;
            buf_waddr <= 11'd0;
            buf_raddr <= 11'd0;
            feed_rd_i <= 10'd0;
            feed_wr_i <= 9'd0; feed_last <= 0;
            feed_pipe_v <= 1'b0;feed_pipe_d<=0;
            reload_pending_mem <= 1'b0;
            reload_index_mem <= 2'd0;
            fifo_reset_count_mem <= 3'd0;
            issued_count_mem <= 0;
                all_issued_mem<=1'b0;row_base_wait<=2;
            returned_count_mem <= 0;
            inflight_count_mem <= 0;
            inflight_empty_mem <= 1'b1;
            burst_active_mem <= 1'b0;
            burst_issued_mem <= 0;
            burst_target_mem <= 0;
            burst_gap_count_mem <= 0;
            diag_written_count_mem <= 0;
            diag_column_mem <= 0;
            fifo_release_mem <= 2'b00;
            inflight_window_ok_q <= 1'b1;
            fifo_reservation_ok_q <= 1'b1;
            reserved_sum_q<=0;
            app_rd_en <= 1'b0;
            app_rd_addr <= 0;
            reader_busy <= 1'b0;
            frame_read_done <= 1'b0;
            reader_index <= 2'd0;
            reader_error <= ERR_NONE;
        end else begin
            feed_pipe_d<=reader_mode_mem && tstate_mem==TS_FEED && feed_pipe_v;
            if (fifo_reset_request)
                fifo_release_mem <= 2'b00;
            else
                fifo_release_mem <= {fifo_release_mem[0], 1'b1};

            request_sync1_mem <= request_toggle_pix;
            request_sync2_mem <= request_sync1_mem;
            index_sync1_mem <= request_index_pix;
            index_sync2_mem <= index_sync1_mem;
            menu_sync1_mem<=request_menu_pix;menu_sync2_mem<=menu_sync1_mem;
            page_sync1_mem<=request_page_pix;page_sync2_mem<=page_sync1_mem;
            mode_sync1_mem <= request_mode_pix;
            mode_sync2_mem <= mode_sync1_mem;
            app_rd_en <= 1'b0;
            if(row_base_wait!=0)row_base_wait<=row_base_wait-1'b1;
            frame_read_done <= 1'b0;
            inflight_window_ok_q <= inflight_window_ok;
            fifo_reservation_ok_q <= fifo_reservation_ok;
            reserved_sum_q<=reserved_words[RES_COUNT_W-1:0];

            if (fifo_reset_count_mem != 0)
                fifo_reset_count_mem <= fifo_reset_count_mem - 1'b1;
            if (burst_gap_count_mem != 0)
                burst_gap_count_mem <= burst_gap_count_mem - 1'b1;

            case ({issue_allowed, sdram_rd_valid})
                2'b10: begin
                    inflight_count_mem <= inflight_count_mem + 1'b1;
                    inflight_empty_mem <= 1'b0;
                end
                2'b01: begin
                    if (!inflight_empty_mem) begin
                        inflight_count_mem <= inflight_count_mem - 1'b1;
                        if (inflight_count_mem == 1)
                            inflight_empty_mem <= 1'b1;
                    end
                end
                default: begin
                    inflight_count_mem <= inflight_count_mem;
                    inflight_empty_mem <= inflight_empty_mem;
                end
            endcase

            if (request_sync2_mem != request_seen_mem) begin
                request_seen_mem <= request_sync2_mem;
                reload_pending_mem <= 1'b1;
                reload_index_mem <= index_sync2_mem;
                reload_mode_mem <= mode_sync2_mem;reload_menu_mem<=menu_sync2_mem;reload_page_mem<=page_sync2_mem;
                if (reader_busy || !inflight_empty_mem) begin
                    reader_busy <= 1'b0;
                    burst_active_mem <= 1'b0;
                    reader_error <= ERR_FRAME_OVERRUN;
                end
            end

            if (reload_pending_mem && inflight_empty_mem) begin
                reload_pending_mem <= 1'b0;
                reader_index <= reload_index_mem;
                reader_mode_mem <= reload_mode_mem;reader_menu_mem<=reload_menu_mem;reader_page_mem<=reload_page_mem;   // 第13课：模式帧边界生效
                t_row_mem <= 8'd0;
                tstate_mem <= TS_FILL;
                fill_word_mem <= 12'd0;
                buf_waddr <= 11'd0;
                buf_raddr <= 11'd0;
                feed_rd_i <= 10'd0;
                feed_wr_i <= 9'd0; feed_last <= 0;
                feed_pipe_v <= 1'b0;feed_pipe_d<=0;
                issued_count_mem <= 0;
                all_issued_mem<=1'b0;row_base_wait<=2;
                returned_count_mem <= 0;
                inflight_count_mem <= 0;
                inflight_empty_mem <= 1'b1;
                burst_active_mem <= 1'b0;
                burst_issued_mem <= 0;
                burst_target_mem <= 0;
                burst_gap_count_mem <= 0;
                diag_written_count_mem <= 0;
                diag_column_mem <= 0;
                fifo_reset_count_mem <= 3'd4;
                reader_busy <= 1'b1;
                reader_error <= ERR_NONE;
            end

            if (start_burst) begin
                burst_active_mem <= 1'b1;
                burst_issued_mem <= 0;
                burst_target_mem <= next_burst_words[BURST_COUNT_W-1:0];
            end

            if (issue_allowed) begin
                app_rd_en <= 1'b1;
                // 第13课修正：缩略图发行填充地址（全顺序），全屏原顺序地址
                app_rd_addr <= reader_mode_mem ? (reader_menu_mem?menu_fill_addr:fill_addr) :
                               (bank_base(reader_index) + issued_count_mem[ADDR_WIDTH-1:0]);
                issued_count_mem <= issued_count_mem + 1'b1;
                if(issued_count_mem==issue_target-1'b1)all_issued_mem<=1'b1;
                if (reader_mode_mem)
                    fill_word_mem <= fill_word_mem + 1'b1;   // 行内发射计数0..1280
                burst_issued_mem <= burst_issued_mem + 1'b1;
                if (burst_issued_mem + 1'b1 == burst_target_mem) begin
                    burst_active_mem <= 1'b0;
                    burst_gap_count_mem <= BURST_GAP_CYCLES;
                end
            end

            if (!DIAG_SYNTH_STREAM && sdram_rd_valid) begin
                returned_count_mem <= returned_count_mem + 1'b1;
                if (reader_mode_mem) begin
                    // 第13课修正：返回顺序写行缓冲（返回序=请求序）；本行1280字齐→待泵
                    buf_waddr <= buf_waddr + 1'b1;
                    if (buf_waddr == row_fill_words-1'b1)
                        tstate_mem <= TS_FWAIT;
                end else if (fifo_full) begin
                    reader_busy <= 1'b0;
                    burst_active_mem <= 1'b0;
                    reader_error <= ERR_FIFO_OVERFLOW;
                end else if (final_return) begin
                    reader_busy <= 1'b0;
                    burst_active_mem <= 1'b0;
                    frame_read_done <= 1'b1;
                end
            end

            // 第13课修正：行供给泵——FWAIT等FIFO腾出320字空间，
            // FEED按显示序（左半stride-4、右半stride-4）把行缓冲泵入异步FIFO
            if (reader_mode_mem) begin
                if (tstate_mem == TS_FWAIT) begin
                    if (fifo_wrusedw <= THUMB_FEED_ROOM)
                        tstate_mem <= TS_FEED;
                end else if (tstate_mem == TS_FEED) begin
                    if (feed_rd_i != 10'd320) begin
                        buf_raddr <= active_feed_addr;
                        feed_rd_i <= feed_rd_i + 1'b1;
                        feed_pipe_v <= 1'b1;
                    end else begin
                        feed_pipe_v <= 1'b0;
                    end
                    if (feed_pipe_d) begin
                        if (feed_last) begin
                            // 本行320字泵完：推进到下一显示行（或全帧240行完成）
                            feed_rd_i <= 10'd0;
                            feed_wr_i <= 9'd0; feed_last <= 0;
                            buf_waddr <= 11'd0;
                            fill_word_mem <= 12'd0;row_base_wait<=2;
                            tstate_mem <= TS_FILL;
                            if (t_row_mem == 8'd239) begin
                                t_row_mem <= 8'd0;
                                reader_busy <= 1'b0;
                                frame_read_done <= 1'b1;
                            end else begin
                                t_row_mem <= t_row_mem + 1'b1;
                            end
                        end else begin
                            feed_wr_i <= feed_wr_i + 1'b1;
                            if (feed_wr_i == 9'd318) feed_last <= 1;
                        end
                    end
                end
            end

            if (DIAG_SYNTH_STREAM && diag_stream_write) begin
                diag_written_count_mem <= diag_written_count_mem + 1'b1;
                diag_column_mem <= (diag_column_mem == 10'd639) ?
                                   10'd0 : diag_column_mem + 1'b1;
                if (diag_written_count_mem == IMAGE_WORDS - 1) begin
                    reader_busy <= 1'b0;
                    frame_read_done <= 1'b1;
                end
            end else if (!DIAG_SYNTH_STREAM && DIAG_RETURN_PATTERN &&
                         sdram_rd_valid) begin
                diag_column_mem <= (diag_column_mem == 10'd639) ?
                                   10'd0 : diag_column_mem + 1'b1;
            end
        end
    end

    // 读侧异步FIFO：工程已有IP（afifo_32_16_256.v内定义rfifo_32_32_512）
    rfifo_32_32_512 #(
        .DATA_WIDTH_W(32), .DATA_WIDTH_R(32),
        .ADDR_WIDTH_W(FIFO_COUNT_W), .ADDR_WIDTH_R(FIFO_COUNT_W),
        .AL_FULL_NUM(FIFO_DEPTH-FIFO_MARGIN), .AL_EMPTY_NUM(2),
        .SHOW_AHEAD_EN(1'b0), .OUTREG_EN("NOREG")
    ) u_read_fifo (
        .rst(fifo_reset), .clkw(mem_clk), .clkr(pix_clk),
        .we(fifo_write_enable), .di(fifo_write_data),
        .re(fifo_raw_read_en), .dout(fifo_raw_data), .valid(fifo_raw_valid),
        .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(fifo_almost_full), .aempty(),
        .wrusedw(fifo_wrusedw), .rdusedw()
    );

    fifo_prefetch_2 #(.DATA_WIDTH(32)) u_prefetch (
        .clk(pix_clk), .rst(fifo_reset), .raw_empty(fifo_empty),
        .raw_valid(fifo_raw_valid), .raw_data(fifo_raw_data),
        .raw_read_en(fifo_raw_read_en), .consume(pixel_pop),
        .out_valid(prefetch_valid), .out_empty(), .out_data(prefetch_data)
    );

    assign pixel_rgb = prefetch_data[23:0];
    assign pixel_valid = prefetch_valid;
    // 第13课：当前帧实际生效的缩略图模式（供顶层消费门控/像素mux，帧边界切换）
    assign thumb_mode_frame = request_mode_pix;
    assign menu_mode_frame=request_menu_pix;
    assign menu_page_frame=request_page_pix;

    // underflow为pix_clk域独立输出，顶层合并为8'h63显示
endmodule
