module bmp_read #(
    // === 第4课新增：SD读超时参数（稳定性优化4）===
    parameter integer CLK_FREQ_HZ        = 100_000_000,
    parameter integer SD_READ_TIMEOUT_MS = 500
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input                       load_abort,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data,

    // === 第4课新增：错误码上报（优化2）===
    output reg [2:0]            bmp_error,   // 0无/1头校验失败/2读超时/3像素截断
    output reg                  load_error,  // 加载失败单拍脉冲

    // === 第4课选做·快速启动 ===
    input                       scan_resume, // 续扫命令（上层提交显示后发出）
    output                      load_running // 正在加载（HDR/WAIT/DATA），供上层清除保持请求
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;

// === 第4课新增：错误码定义 ===
localparam ERR_NONE      = 3'd0;
localparam ERR_HEADER    = 3'd1;
localparam ERR_TIMEOUT   = 3'd2;
localparam ERR_TRUNCATED = 3'd3;

// === 第4课新增：SD读超时阈值（时钟周期数）===
localparam integer TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;
// === 第4课新增：严格校验字段（优化1）===
reg [31:0] dib_size;        // DIB头大小（偏移14-17），必须>=40
reg [15:0] planes;          // 平面数（偏移26-27），必须为1
// === 第4课新增：超时与像素完整性（优化4/5）===
reg [31:0] sd_timeout_cnt;
reg [31:0] pixel_count;
// === 第4课选做·快速启动：扫描挂起标志（加载完后回ST_SCAN续扫）===
reg        scan_suspended;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

wire header_match;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
// === 第4课新增 ===
wire [31:0] expected_pixels;
wire        sd_read_timeout;

assign ready = (state == ST_IDLE);
assign load_running = (state == ST_LOAD_HDR) || (state == ST_LOAD_WAIT) || (state == ST_LOAD_DATA);
// 第4课优化1：严格校验——在官方6项基础上新增DIB头大小/平面数/像素偏移范围/文件大小合理性
assign header_match = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (dib_size >= 32'd40) &&                  // DIB头大小>=40
                      (width[15:0]  == bmp_width) &&
                      (height[15:0] == bmp_height) &&
                      (planes == 16'd1) &&                     // 平面数=1
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0) &&
                      (pixel_offset >= 32'd54) &&              // 像素偏移>=54
                      (pixel_offset < file_len) &&             // 像素偏移<文件大小
                      (file_len >= pixel_offset + expected_pixels * 32'd3); // 文件装得下全部像素
assign expected_pixels = {16'd0, bmp_width} * {16'd0, bmp_height};
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign file_sector_count = (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_match = scan_sector + file_sector_count;
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size     <= 32'd0;
        planes       <= 16'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_size[7:0] <= sd_sec_read_data;    // 第4课新增
            10'd15: dib_size[15:8] <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd26: planes[7:0] <= sd_sec_read_data;      // 第4课新增
            10'd27: planes[15:8] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

// === 第4课优化4：SD读超时计数——有字节活动/扇区结束/写应答即清零，连续500ms无活动判超时 ===
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sd_timeout_cnt <= 32'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR) ||
                 (state == ST_LOAD_WAIT) || (state == ST_LOAD_DATA)) begin
        if (sd_sec_read_data_valid || sd_sec_read_end || write_req_ack)
            sd_timeout_cnt <= 32'd0;
        else
            sd_timeout_cnt <= sd_timeout_cnt + 32'd1;
    end else begin
        sd_timeout_cnt <= 32'd0;
    end
end

assign sd_read_timeout = (sd_timeout_cnt >= TIMEOUT_CYCLES[31:0]);

// === 第4课优化5：像素完整性计数——每输出一个完整像素+1，进入加载头时清零 ===
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pixel_count <= 32'd0;
    end else if (state == ST_LOAD_HDR) begin
        pixel_count <= 32'd0;
    end else if ((state == ST_LOAD_DATA) && bmp_data_valid && (bmp_byte_idx == 2'd2)) begin
        pixel_count <= pixel_count + 32'd1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        bmp_error         <= ERR_NONE;
        load_error        <= 1'b0;
        scan_suspended    <= 1'b0;
    end else if (!sd_init_done || load_abort) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        bmp_error         <= ERR_NONE;
        load_error        <= 1'b0;
        scan_suspended    <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        load_error       <= 1'b0;   // 单拍脉冲，默认清零

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_resume && scan_suspended) begin
                    // 第4课选做·快速启动：上层已提交显示，从挂起点续扫剩余图片
                    scan_suspended   <= 1'b0;
                    sd_sec_read_addr <= scan_sector;
                    state            <= ST_SCAN;
                end else if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    bmp_error        <= ERR_NONE;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    bmp_error           <= ERR_NONE;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_read_timeout) begin
                    // 第4课优化4：扫描期SD读超时——终止扫描，用已找到的结果继续，不死锁
                    bmp_error   <= ERR_TIMEOUT;
                    scan_done   <= 1'b1;
                    sd_sec_read <= 1'b0;
                    state       <= ST_IDLE;
                end else if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    // 第4课选做·快速启动：扫描途中收到加载请求（首图发现后立即加载），
                    // 在扇区边界挂起扫描转去加载，加载完回ST_SCAN续扫；
                    // 本扇区恰好找到最后一张时不挂起，让扫描正常完成
                    if (load_start && !(header_match && (scan_found_total + 3'd1 >= scan_target_count))) begin
                        if (header_match) begin
                            scan_found_valid  <= 1'b1;
                            scan_found_sector <= scan_sector;
                            scan_found_total  <= scan_found_total + 3'd1;
                        end
                        scan_sector         <= header_match ? next_scan_sector_if_match : next_scan_sector_if_miss;
                        scan_suspended      <= 1'b1;
                        load_sector_latched <= load_sector;
                        sd_sec_read_addr    <= load_sector;
                        state               <= ST_LOAD_HDR;
                    end else if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        // 第4课优化3：坏图快速跳过——有BM签名但校验失败按文件大小快跳，无签名跳1扇区
                        if ((header_0 == "B") && (header_1 == "M")) begin
                            if (next_scan_sector_if_match > scan_max_sector) begin
                                scan_done <= 1'b1;
                                state     <= ST_IDLE;
                            end else begin
                                sd_sec_read_addr <= next_scan_sector_if_match;
                                scan_sector      <= next_scan_sector_if_match;
                            end
                        end else if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_read_timeout) begin
                    // 第4课优化4：读头超时
                    bmp_error   <= ERR_TIMEOUT;
                    load_error  <= 1'b1;
                    sd_sec_read <= 1'b0;
                    state       <= ST_IDLE;
                end else if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        // 第4课优化2：头校验失败上报错误码（官方是静默回IDLE）
                        bmp_error  <= ERR_HEADER;
                        load_error <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (sd_read_timeout) begin
                    // 第4课优化4：等写应答超时
                    bmp_error  <= ERR_TIMEOUT;
                    load_error <= 1'b1;
                    write_req  <= 1'b0;
                    state      <= ST_IDLE;
                end else if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_read_timeout) begin
                    // 第4课优化4：读数据超时
                    bmp_error   <= ERR_TIMEOUT;
                    load_error  <= 1'b1;
                    sd_sec_read <= 1'b0;
                    state       <= ST_IDLE;
                end else if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (bmp_len_cnt >= file_len) begin
                        if (pixel_count < expected_pixels) begin
                            // 第4课优化5：像素截断——文件读完但像素不够，报错误而不是显示撕裂图
                            bmp_error  <= ERR_TRUNCATED;
                            load_error <= 1'b1;
                        end
                        // 快速启动：加载完先回IDLE等上层提交，收到scan_resume才续扫
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
