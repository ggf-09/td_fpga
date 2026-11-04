`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// 第8课：media_frame_loader（帧加载器）
// 来源：第8课参考代码，针对本工程做两处适配：
//   1) 新增 WRITE_V_FLIP 垂直翻转写（承接原 frame_fifo_write 的功能：
//      BMP文件自下而上存储，写SDRAM时倒序写行，读出即为正图）；
//   2) fifo_mem 加 force_ram 属性，强制映射BRAM，避免512x32寄存器堆吃LUT。
// 时钟域：clk = sd_card_clk(100MHz)，与BMP解析同域，像素流零跨域；
//         burst写命令由顶层 media_sdram_write_cdc 转到ext_mem_clk(125MHz)域。
// -----------------------------------------------------------------------------
module media_frame_loader #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer IMAGE_WORDS = 307200,
    parameter integer FIFO_DEPTH = 512,
    parameter integer BURST_SIZE = 128,
    parameter integer STALL_TIMEOUT = 65535,
    parameter integer WRITE_V_FLIP = 1,      // 1: 写SDRAM时垂直翻转（抵消BMP自下而上存储）
    parameter integer FRAME_WIDTH  = 640,
    parameter integer FRAME_HEIGHT = 480, MENU_SUPPORT=0
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  load_start,       // 启动加载（单拍脉冲）
    input  wire                  menu_load,
    input  wire [1:0]            image_index,      // 目标图片编号（0~3，即bank编号）
    input  wire                  pixel_valid,      // 像素有效
    input  wire [23:0]           pixel_rgb,        // 像素RGB
    input  wire                  frame_commit,     // 帧提交（一帧像素发送完成）
    input  wire [7:0]            decode_error,     // 解码错误（来自BMP解码侧，非0即失败）
    // 页切换软失效（替代原硬复位）：清4槽完成位，但keep_valid时保留keep_slot槽——
    // 重叠加载期间旧封面靠该位继续通过顶层显示门控，淡出不被瞬间拉黑。
    // 受理重载时SEQ必在DONE态，loader必空闲，软清与硬复位等价（其余状态load_start都重初始化）。
    input  wire                  cache_invalidate,
    input  wire                  keep_valid,
    input  wire [1:0]            keep_slot,
    output wire                  load_busy,        // 加载中
    output reg                   load_done,        // 加载完成（单拍，成功/失败都拉）
    output reg  [3:0]            image_complete,   // 4张图片加载完成标记
    output reg  [7:0]            memory_error,     // 错误码
    input  wire                  controller_init_done, // SDRAM控制器初始化完成
    input  wire                  controller_busy,      // SDRAM控制器忙（保留，控制器内部处理）
    input  wire                  refresh_active,       // 刷新有效（保留，控制器内部处理）
    output reg                   app_wr_en,            // 写使能
    output reg  [ADDR_WIDTH-1:0] app_wr_addr,         // 写地址
    output reg  [3:0]            app_wr_mask,          // 写字节掩码
    output reg  [31:0]           app_wr_data           // 写数据
);
    localparam ERR_NONE          = 8'h00;
    localparam ERR_NOT_ACTIVE    = 8'h41;
    localparam ERR_FIFO_OVERFLOW = 8'h42;
    localparam ERR_PIXEL_COUNT   = 8'h43;
    localparam ERR_DECODE        = 8'h44;
    localparam ERR_SHORT_FRAME   = 8'h45;
    localparam ERR_WRITE_STALL   = 8'h46;

    localparam integer PTR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam [PTR_WIDTH:0] EFFECTIVE_BURST =
        (BURST_SIZE < FIFO_DEPTH) ? BURST_SIZE : FIFO_DEPTH;
    localparam [ADDR_WIDTH-1:0] BANK0_BASE = 0;
    localparam [ADDR_WIDTH-1:0] BANK1_BASE = IMAGE_WORDS;
    localparam [ADDR_WIDTH-1:0] BANK2_BASE = IMAGE_WORDS * 2;
    localparam [ADDR_WIDTH-1:0] BANK3_BASE = IMAGE_WORDS * 3;

    // 垂直翻转地址映射（与原 frame_fifo_write 相同）：
    // 像素流第0行 -> 内存最后一行；行尾地址回跳 (FRAME_WIDTH*2-1)
    localparam [ADDR_WIDTH-1:0] VFLIP_FIRST_ADDR_OFFSET = (FRAME_HEIGHT - 1) * FRAME_WIDTH;
    localparam [ADDR_WIDTH-1:0] VFLIP_LINE_JUMP         = (FRAME_WIDTH * 2) - 1;

    reg active,active_menu;
    wire menu_request=MENU_SUPPORT!=0 && menu_load;
    reg [1:0] active_image;
    reg commit_seen;
    localparam integer PIXEL_COUNT_W=IMAGE_WORDS<2?1:$clog2(IMAGE_WORDS+1);
    localparam integer STALL_COUNT_W=STALL_TIMEOUT<2?1:$clog2(STALL_TIMEOUT+1);
    reg [PIXEL_COUNT_W-1:0] pixels_received;
    reg [PIXEL_COUNT_W-1:0] pixels_written;
    wire [ADDR_WIDTH-1:0] written_address=pixels_written;
    reg counts_match, drain_ready;
    reg [STALL_COUNT_W-1:0] stall_count;
    // 强制BRAM：同步写+寄存读，单时钟SDP，避免512x32寄存器堆
    reg [31:0] fifo_mem [0:FIFO_DEPTH-1];  /* fehdl force_ram=1, ram_style="bram" */
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH:0] fifo_count;
    reg burst_active;
    reg [PTR_WIDTH:0] burst_remaining;
    // 第8课新增：垂直翻转行内计数与运行地址
    reg [15:0] wr_x;
    reg [ADDR_WIDTH-1:0] wr_addr_cur;
    wire pop_allowed;
    wire push_allowed;
    wire start_burst;
    wire [PTR_WIDTH:0] next_burst_words;

    assign load_busy = active;
    // 延用的控制器会消费连续的 App_wr_en burst 并内部处理busy/refresh，
    // 这些状态输出不是逐字ready信号，不能拆开进行中的写burst。
    assign start_burst = active && controller_init_done && !burst_active &&
                         fifo_count != 0 &&
                         (fifo_count >= EFFECTIVE_BURST || commit_seen);
    assign next_burst_words = (fifo_count >= EFFECTIVE_BURST) ?
                              EFFECTIVE_BURST : fifo_count;
    assign pop_allowed = active && controller_init_done && burst_active &&
                         fifo_count != 0;
    assign push_allowed = active && pixel_valid &&
                          (fifo_count < FIFO_DEPTH || pop_allowed);

    function [ADDR_WIDTH-1:0] bank_base;
        input [1:0] index;
        begin
            case (index)
                2'd0: bank_base = BANK0_BASE;
                2'd1: bank_base = BANK1_BASE;
                2'd2: bank_base = BANK2_BASE;
                default: bank_base = BANK3_BASE;
            endcase
        end
    endfunction

    task fail_load;
        input [7:0] code;
        begin
            memory_error <= code;
            active <= 1'b0;
            burst_active <= 1'b0;
            burst_remaining <= 0;
            load_done <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;active_menu<=0;
            counts_match <= 0; drain_ready <= 0;
            active_image <= 2'd0;
            commit_seen <= 1'b0;
            pixels_received <= 32'd0;
            pixels_written <= 32'd0;
            stall_count <= 32'd0;
            wr_ptr <= {PTR_WIDTH{1'b0}};
            rd_ptr <= {PTR_WIDTH{1'b0}};
            fifo_count <= {(PTR_WIDTH+1){1'b0}};
            burst_active <= 1'b0;
            burst_remaining <= 0;
            wr_x <= 16'd0;
            wr_addr_cur <= {ADDR_WIDTH{1'b0}};
            load_done <= 1'b0;
            image_complete <= 4'd0;
            memory_error <= ERR_NONE;
            app_wr_en <= 1'b0;
            app_wr_addr <= {ADDR_WIDTH{1'b0}};
            app_wr_mask <= 4'b0000;
            app_wr_data <= 32'd0;
        end else begin
            load_done <= 1'b0;
            app_wr_en <= 1'b0;
            counts_match <= pixels_received == IMAGE_WORDS && pixels_written == IMAGE_WORDS;
            drain_ready <= active && commit_seen && fifo_count == 0 && !pop_allowed && !burst_active;

            if (load_start && !active) begin
                active <= 1'b1;
                drain_ready <= 0; counts_match <= 0;
                active_image <= image_index;active_menu<=menu_request;
                commit_seen <= 1'b0;
                pixels_received <= 32'd0;
                pixels_written <= 32'd0;
                stall_count <= 32'd0;
                wr_ptr <= {PTR_WIDTH{1'b0}};
                rd_ptr <= {PTR_WIDTH{1'b0}};
                fifo_count <= {(PTR_WIDTH+1){1'b0}};
                burst_active <= 1'b0;
                burst_remaining <= 0;
                // 第8课：翻转写首地址 = bank基址 + 最后一行偏移
                wr_x <= 16'd0;
                wr_addr_cur <= (menu_request?IMAGE_WORDS*4:bank_base(image_index)) + VFLIP_FIRST_ADDR_OFFSET;
                memory_error <= ERR_NONE;
                if(!menu_request)case (image_index)
                    2'd0: image_complete[0] <= 1'b0;
                    2'd1: image_complete[1] <= 1'b0;
                    2'd2: image_complete[2] <= 1'b0;
                    default: image_complete[3] <= 1'b0;
                endcase
            end

            if (active) begin
                if (decode_error != 0) begin
                    fail_load(ERR_DECODE);
                end else if (pixel_valid && pixels_received >= IMAGE_WORDS) begin
                    fail_load(ERR_PIXEL_COUNT);
                end else if (pixel_valid && !push_allowed) begin
                    fail_load(ERR_FIFO_OVERFLOW);
                end else begin
                    if (start_burst) begin
                        burst_active <= 1'b1;
                        burst_remaining <= next_burst_words;
                    end

                    if (push_allowed) begin
                        fifo_mem[wr_ptr] <= {8'h00, pixel_rgb};
                        wr_ptr <= wr_ptr + 1'b1;
                        pixels_received <= pixels_received + 1'b1;
                    end

                    if (pop_allowed) begin
                        app_wr_en <= 1'b1;
                        if (WRITE_V_FLIP) begin
                            // 第8课：垂直翻转——行内地址+1，行尾回跳 (2*WIDTH-1)
                            app_wr_addr <= wr_addr_cur;
                            if (wr_x == FRAME_WIDTH[15:0] - 16'd1) begin
                                wr_x <= 16'd0;
                                wr_addr_cur <= wr_addr_cur - VFLIP_LINE_JUMP;
                            end else begin
                                wr_x <= wr_x + 16'd1;
                                wr_addr_cur <= wr_addr_cur + 1'b1;
                            end
                        end else begin
                            app_wr_addr <= (active_menu?IMAGE_WORDS*4:bank_base(active_image)) + written_address;
                        end
                        app_wr_data <= fifo_mem[rd_ptr];
                        app_wr_mask <= 4'b0000;
                        rd_ptr <= rd_ptr + 1'b1;
                        pixels_written <= pixels_written + 1'b1;
                        stall_count <= 32'd0;
                        if (burst_remaining == 1) begin
                            burst_active <= 1'b0;
                            burst_remaining <= 0;
                        end else begin
                            burst_remaining <= burst_remaining - 1'b1;
                        end
                    end else if (fifo_count != 0 &&
                                 (commit_seen || fifo_count >= EFFECTIVE_BURST)) begin
                        if (stall_count == STALL_TIMEOUT)
                            fail_load(ERR_WRITE_STALL);
                        else
                            stall_count <= stall_count + 1'b1;
                    end else begin
                        stall_count <= 32'd0;
                    end

                    case ({push_allowed, pop_allowed})
                        2'b10: fifo_count <= fifo_count + 1'b1;
                        2'b01: fifo_count <= fifo_count - 1'b1;
                        default: fifo_count <= fifo_count;
                    endcase

                    if (frame_commit)
                        commit_seen <= 1'b1;

                    if (drain_ready && commit_seen && fifo_count == 0 && !pop_allowed &&
                        !burst_active) begin
                        if (!counts_match) begin
                            fail_load(ERR_SHORT_FRAME);
                        end else begin
                            if(!active_menu)case (active_image)
                                2'd0: image_complete[0] <= 1'b1;
                                2'd1: image_complete[1] <= 1'b1;
                                2'd2: image_complete[2] <= 1'b1;
                                default: image_complete[3] <= 1'b1;
                            endcase
                            active <= 1'b0;
                            load_done <= 1'b1;
                        end
                    end
                end
            end else if (pixel_valid) begin
                memory_error <= ERR_NOT_ACTIVE;
            end

            // 软失效（替代原硬复位）：清4槽完成位，但keep_valid时保留keep_slot槽——
            // 重叠加载期间旧封面靠该位继续通过顶层显示门控，淡出不被瞬间拉黑。
            // 受理重载时SEQ必在DONE态、loader必空闲（active=0），上面的主体不会动作，
            // 软清与硬复位等价（其余状态load_start都重初始化）。
            // 放在块尾靠"后写覆盖前写"取得最高优先级，而不套else-if层级——
            // 中间多一层分支会破坏fifo_mem的同步写BRAM模板（TD报SYN-5042退化为逻辑）。
            if (cache_invalidate) begin
                active <= 1'b0;
                load_done <= 1'b0;
                app_wr_en <= 1'b0;
                burst_active <= 1'b0;
                image_complete <= image_complete & (keep_valid ? (4'b0001 << keep_slot) : 4'b0000);
            end
        end
    end
endmodule
