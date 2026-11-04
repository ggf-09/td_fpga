`timescale 1ns/1ps

// R3'-A: stream real audio content from the TF card and feed it into the
// existing HDMI audio chain (docs/29 rev: "what actually wins"). This module
// sits between the SD sector-read infrastructure and the PCM sample
// interface, using a dual-port BRAM circular buffer to absorb the ~12.5x
// rate mismatch between TF reads (~1.2 MB/s burst) and audio consumption
// (96 KB/s at 48 kHz 16-bit mono).
//
// Architecture:
//   TF sector bytes (mem_clk domain, byte-serial)
//     -> pair into 16-bit samples -> write into BRAM circular buffer
//   Audio sample ticks (pixel_clk domain, ~48 kHz)
//     -> read from BRAM -> output on valid/ready PCM interface
//
// The write side uses a sector-level state machine: issue one sector read,
// fill 256 samples (512 bytes), then issue the next. The read side consumes
// at the audio sample rate. Pointer crossing uses gray-coded 2FF sync (the
// established idiom). Buffer underflow outputs silence (zeros) with
// sample_valid still asserted, so the downstream HDMI chain never stalls.
//
// Data format: raw 16-bit signed little-endian PCM, 48 kHz mono. The PC
// tool (tools/make_audio_corpus.py) converts any WAV to this format before
// writing to the TF card. Endianness: TF bytes arrive LSB first.
//
// 安路适配：buffer加 fehdl force_ram 属性强制推断BRAM（4096x16用寄存器放不下EG4S20）
// 安路适配2：sd_lba改为cur_lba组合直出（原版在WS_REQ拍末才寄存sd_lba，而本工程
//   sd_sector_adapter在受理请求的同一拍锁存地址，寄存版会读到上一扇区/首读扇区0）
// 安路适配3：BRAM读写拆成独立专用always块（双钟BRAM推断模板，原版读写混在状态机
//   大块里导致TD读口BRAM推断失败SYN-5042）；读口改同步读，buf_rdata提前一拍寄存，
//   消费拍直接取用——sample_tick间隔520拍，rd_ptr早已稳定，接口时序与原版图灵一致
// 安路适配4：补上写侧流控（原版严重bug：level_wr声明了却从未使用，写状态机读完
//   一扇区立刻请求下一扇区，SD全速(~1MB/s)下约8ms就写满4096样本环形缓冲，随后不停
//   覆盖未消费数据，音乐被绞成杂音——上板实测全是噪声即此因）。现按12位指针回绕
//   正确计算空闲量，余量不足一扇区(256样本)时在WS_WAIT等待读侧消费，并保留1样本
//   空闲避免wr_ptr==rd_ptr的空/满歧义
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 12,         // 4096 x 16-bit = 8 KB
    parameter integer SAMPLES_PER_SECTOR = 256 // 512 bytes / 2
) (
    // write side: mem_clk domain (SD SPI engine clock)
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,        // level: stream active
    input  wire [31:0] start_lba,          // first data sector (after WAV header)
    input  wire [31:0] total_sectors,      // audio data extent in sectors
    output wire        sd_req,             // request a sector read
    output wire [31:0] sd_lba,             // 组合直出cur_lba：请求受理拍地址必须已有效
    input  wire        sd_busy,
    input  wire        sd_valid,           // one byte per valid pulse
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,      // 0..511 within sector
    input  wire        sd_done,
    input  wire [7:0]  sd_error,

    // read side: pixel_clk domain (audio chain clock)
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,        // ~48 kHz pulse: consume one sample
    output reg  signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,       // from downstream (always 1 in our chain)

    // status (read side)
    output reg  [31:0] sample_counter,     // samples consumed (for OSD)
    output wire        stream_active,      // play_enable && not ended
    output wire        stream_end,         // all data consumed
    output wire        buffer_low          // < 25% remaining (for OSD/status)
);
    // ---------------- circular buffer ----------------
    reg [15:0] buffer [0:(1<<ADDR_WIDTH)-1] /* fehdl force_ram=1, ram_style="bram" */;
    reg [ADDR_WIDTH-1:0] wr_ptr;    // write pointer (wr_clk domain)
    reg [ADDR_WIDTH-1:0] rd_ptr;    // read pointer (rd_clk domain)
    reg [15:0] buf_rdata;           // BRAM同步读数据（无复位，专用读口寄存器）

    // write state sync to read domain (quasi-static, 2FF is safe)
    reg [2:0] wstate_sync1, wstate_sync2;

    // gray-coded sync: wr_ptr -> rd_clk domain
    reg [ADDR_WIDTH-1:0] wr_gray;
    reg [ADDR_WIDTH-1:0] wr_gray_sync1, wr_gray_sync2;
    // gray-coded sync: rd_ptr -> wr_clk domain
    reg [ADDR_WIDTH-1:0] rd_gray;
    reg [ADDR_WIDTH-1:0] rd_gray_sync1, rd_gray_sync2;

    function [ADDR_WIDTH-1:0] to_gray;
        input [ADDR_WIDTH-1:0] b;
        begin
            to_gray = b ^ (b >> 1);
        end
    endfunction

    function [ADDR_WIDTH-1:0] from_gray;
        input [ADDR_WIDTH-1:0] g;
        reg [ADDR_WIDTH-1:0] b;
        integer i;
        begin
            b[ADDR_WIDTH-1] = g[ADDR_WIDTH-1];
            for (i = ADDR_WIDTH-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            from_gray = b;
        end
    endfunction

    // synchronized pointers (each in the other domain)
    wire [ADDR_WIDTH-1:0] wr_ptr_in_rd = from_gray(wr_gray_sync2);
    wire [ADDR_WIDTH-1:0] rd_ptr_in_wr = from_gray(rd_gray_sync2);

    // 安路适配4：写侧空闲量（12位指针回绕减法，结果即mod 4096的正确空闲样本数）
    wire [ADDR_WIDTH-1:0] room_wr = rd_ptr_in_wr - wr_ptr - 1'b1;
    // 余量严格大于一扇区才发新读：写完至少剩1样本空闲，避免wr==rd的空/满歧义
    wire buffer_has_room = (room_wr > SAMPLES_PER_SECTOR);
    // fill level in read domain (for buffer_low status)
    wire [ADDR_WIDTH:0] level_rd = {1'b0, wr_ptr_in_rd} - {1'b0, rd_ptr};

    // ---------------- write side state machine ----------------
    localparam [2:0] WS_IDLE  = 3'd0;
    localparam [2:0] WS_REQ   = 3'd1;
    localparam [2:0] WS_FILL  = 3'd2;
    localparam [2:0] WS_DONE  = 3'd3;
    localparam [2:0] WS_END   = 3'd4;
    localparam [2:0] WS_WAIT  = 3'd5;   // 安路适配4：缓冲将满，等读侧腾出空间
    reg [2:0]  wstate;
    wire wstate_ended = (wstate == WS_END);
    reg [31:0] cur_lba;
    reg [31:0] sectors_read;
    reg [7:0]  lo_byte;             // little-endian pair assembly
    reg        lo_pending;

    assign sd_req = (wstate == WS_REQ);
    assign sd_lba = cur_lba;   // 组合直出：WS_REQ期间cur_lba已是目标扇区
    assign stream_active = play_enable && (wstate != WS_END);
    assign stream_end = (wstate == WS_END);
    assign buffer_low = (level_rd < (1 << (ADDR_WIDTH-2))); // < 25%

    // 写口专用块（双钟BRAM推断模板）：WS_FILL中凑齐一对小端字节即写一个样本
    wire buf_wr_en = (wstate == WS_FILL) && sd_valid && lo_pending;
    always @(posedge wr_clk) begin
        if (buf_wr_en)
            buffer[wr_ptr] <= {sd_byte, lo_byte};
    end

    // 读口专用块（同步读，无复位）：每拍把rd_ptr指向的样本打入buf_rdata；
    // sample_tick间隔≈520拍且消费之间rd_ptr不变，消费拍buf_rdata必为当前样本
    always @(posedge rd_clk) begin
        buf_rdata <= buffer[rd_ptr];
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wstate         <= WS_IDLE;
            cur_lba        <= 32'd0;
            sectors_read   <= 32'd0;
            wr_ptr         <= {ADDR_WIDTH{1'b0}};
            lo_pending     <= 1'b0;
            lo_byte        <= 8'd0;
            rd_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            rd_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            rd_gray        <= {ADDR_WIDTH{1'b0}};
        end else begin
            // gray-code sync of rd_ptr into wr domain
            rd_gray      <= to_gray(rd_ptr);
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;

            case (wstate)
            WS_IDLE: begin
                if (play_enable && start_lba != 32'd0 && total_sectors != 32'd0) begin
                    cur_lba      <= start_lba;
                    sectors_read <= 32'd0;
                    wr_ptr       <= {ADDR_WIDTH{1'b0}};
                    lo_pending   <= 1'b0;
                    wstate       <= WS_REQ;
                end
            end
            WS_REQ: begin
                if (!sd_busy) begin
                    wstate  <= WS_FILL;   // sd_lba组合直出，无需寄存
                end
            end
            WS_FILL: begin
                if (sd_valid) begin
                    if (!lo_pending) begin
                        lo_byte    <= sd_byte;
                        lo_pending <= 1'b1;
                    end else begin
                        // buffer写由专用写口块完成（buf_wr_en同条件）
                        wr_ptr         <= wr_ptr + 1'b1;
                        lo_pending     <= 1'b0;
                    end
                end
                if (sd_done) begin
                    if (sd_error != 8'd0) begin
                        wstate <= WS_END;  // sector error: stop streaming
                    end else begin
                        sectors_read <= sectors_read + 1'b1;
                        cur_lba      <= cur_lba + 1'b1;
                        if (sectors_read + 1'b1 >= total_sectors)
                            wstate <= WS_END;
                        else if (buffer_has_room)
                            wstate <= WS_REQ;
                        else
                            wstate <= WS_WAIT;   // 安路适配4：缓冲将满，等消费
                    end
                end
            end
            WS_DONE: wstate <= WS_REQ;  // unused, reserved
            WS_WAIT: if (buffer_has_room) wstate <= WS_REQ;  // 安路适配4
            WS_END: begin
                // stay ended until play_enable drops
                if (!play_enable)
                    wstate <= WS_IDLE;
            end
            default: wstate <= WS_IDLE;
            endcase

            // 流控由WS_WAIT状态实现（见安路适配4）：原版这里的"implicit flow
            // control"注释是错的——没有任何逻辑阻止写侧连续请求扇区
        end
    end

    // ---------------- read side ----------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr         <= {ADDR_WIDTH{1'b0}};
            sample_out     <= 16'sd0;
            sample_valid   <= 1'b0;
            sample_counter <= 32'd0;
            wr_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            wr_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            wr_gray        <= {ADDR_WIDTH{1'b0}};
            wstate_sync1   <= 3'd0;
            wstate_sync2   <= 3'd0;
        end else begin
            // gray-code sync of wr_ptr into rd domain
            wr_gray      <= to_gray(wr_ptr);
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            wstate_sync1 <= wstate;
            wstate_sync2 <= wstate_sync1;

            sample_valid <= 1'b0;

            if (sample_tick && sample_ready) begin
                if (level_rd >= SAMPLES_PER_SECTOR || (wstate_sync2 == 3'd4 && level_rd > 0)) begin
                    // enough data (or stream ended with residual): play
                    // buf_rdata为提前一拍寄存的BRAM同步读数据（rd_ptr上拍至今未变）
                    sample_out   <= buf_rdata;
                    rd_ptr       <= rd_ptr + 1'b1;
                    sample_valid <= 1'b1;
                    sample_counter <= sample_counter + 1'b1;
                end else begin
                    // prefill or underflow: silence, don't consume
                    sample_out   <= 16'sd0;
                    sample_valid <= 1'b1;
                end
            end

            if (!play_enable) begin
                rd_ptr         <= {ADDR_WIDTH{1'b0}};
                sample_counter <= 32'd0;
            end
        end
    end
endmodule
