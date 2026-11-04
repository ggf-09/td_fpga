`timescale 1ns/1ps

// Loads a card-resident UTF-8 LRC and FONT.BIN. The FAT streamer has already
// serialized the file bytes; parsing runs after the LRC transfer so the SD
// card can be handed to the WAV player before playback starts.
module fat_lrc_loader #(
    parameter integer CUE_BITS=7, TEXT_BITS=11,
    parameter integer MAX_CUES=126, MAX_TEXT=2048, KARAOKE=0
) (
    input wire clk, rst_n,
    input wire start_font, start_lrc,
    input wire start_timing, timing_clk,
    input wire [11:0] timing_read_addr,
    output wire [7:0] timing_read_data,   // BRAM32K直出（已是同步读一拍延迟，勿再寄存）
    output reg timing_available, timing_ready,
    input wire file_valid,
    input wire [7:0] file_byte,
    input wire [31:0] file_offset,
    input wire file_done,
    input wire [7:0] file_error,
    output reg font_ready,
    output reg lyric_ready,
    output reg parse_done,
    output reg [CUE_BITS-1:0] cue_count,
    output reg font_we,
    output reg [11:0] font_addr,
    output reg [15:0] font_data,
    output reg text_we,
    output reg [TEXT_BITS-1:0] text_addr,
    output reg [7:0] text_data,
    output reg title_we,
    output reg [4:0] title_addr,
    output reg [7:0] title_data,
    output reg [4:0] title_count,
    output reg cue_we,
    output reg [CUE_BITS-1:0] cue_index,
    output reg [15:0] cue_start,
    output reg [TEXT_BITS-1:0] cue_base,
    output reg [4:0] cue_len
);
    localparam [2:0] MODE_IDLE=0, MODE_FONT=1, MODE_LRC=2, MODE_PARSE=3, MODE_TIMING=4;
    localparam [2:0] P_FETCH=0, P_WAIT=1, P_BYTE=2,
                     P_MAP_READ=3, P_MAP_CHECK=4, P_MAP_EMIT=5, P_LIMIT=6;
    localparam [2:0] L_SEEK=0, L_TIME=1, L_TEXT=2, L_SKIP=3, L_TITLE=4;
    reg [2:0] mode;
    reg [2:0] line_mode;
    reg [2:0] pstate;
    // raw[0:4095] 已迁移到 BRAM32K（u_raw_ram），行为与推断BRAM一致（同步读/NORMAL写）
    reg [7:0] raw_q;
    wire [7:0] raw_mem_q, timing_ram_q;
    reg [15:0] font_map [0:255];
    reg [7:0] font_low, map_low;
    reg font_bad, lrc_bad;
    reg [12:0] raw_len;
    reg [12:0] ptr;
    // raw_mem_q/raw_q 原声明已并入上方 BRAM32K 信号区
    reg [3:0] time_stage;
    reg [15:0] time_acc;
    wire [15:0] time_step=time_stage==3 ? (time_acc<<2)+(time_acc<<1) : (time_acc<<3)+(time_acc<<1);
    reg [15:0] line_time;
    reg [TEXT_BITS-1:0] line_base;
    reg [TEXT_BITS:0] text_count;
    reg [4:0] line_len;
    reg [15:0] utf_code, map_query;
    reg [1:0] utf_left;
    reg [7:0] map_index;
    reg [15:0] map_q;
    reg map_hit, map_last;
    reg ptr_finished;
    wire digit = (raw_q >= "0" && raw_q <= "9");
    wire [3:0] digit_value = raw_q - "0";

    reg [3:0] timing_magic;
    reg [11:0] timing_char_count, timing_received;
    reg timing_header_ok;
    wire timing_write = KARAOKE != 0 && mode == MODE_TIMING && file_valid &&
                        file_offset >= 9216 && file_offset < 12288;
    wire lrc_write = mode == MODE_LRC && file_valid && file_offset < 4096;
    wire [11:0] timing_write_addr = file_offset[11:0] - 12'd1024;
    wire [11:0] raw_sd_addr = lrc_write ? file_offset[11:0] :
                              timing_write ? timing_write_addr : ptr[11:0];
    // Port A first buffers/parses UTF-8, then reuses the same RAM for the
    // timing bytes. Port B belongs to video. Timing is loaded after parsing
    // and remains stable until ready is withdrawn on a song change.
    // Port A（clk）：加载写入 / 解析读取；Port B（timing_clk）：卡拉OK计时只读
    ram32k_dp8 u_raw_ram (
        .clka(clk), .wea(lrc_write || timing_write), .addra(raw_sd_addr), .dia(file_byte), .doa(raw_mem_q),
        .clkb(timing_clk), .addrb(timing_read_addr), .dob(timing_ram_q)
    );
    always @(posedge clk) begin
        raw_q <= raw_mem_q;
        map_q <= font_map[map_index];
    end
    generate if (KARAOKE != 0) begin:g_timing_port
        // BRAM32K 同步读输出即一拍延迟，与原"寄存器读推断RAM"逐拍等价
        assign timing_read_data = timing_ram_q;
    end else begin:g_no_timing
        assign timing_read_data = 8'd0;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode <= MODE_IDLE; pstate <= P_LIMIT; line_mode <= L_SEEK;
            font_ready <= 0; lyric_ready <= 0; parse_done <= 0;
            timing_magic <= 0; timing_char_count <= 0; timing_received <= 0;
            timing_header_ok <= 0; timing_available <= 0; timing_ready <= 0;
            font_we <= 0; font_addr <= 0; font_data <= 0;
            text_we <= 0; text_addr <= 0; text_data <= 0;
            title_we <= 0; title_addr <= 0; title_data <= 0; title_count <= 0;
            cue_we <= 0; cue_index <= 0; cue_start <= 0;
            cue_base <= 0; cue_len <= 0; cue_count <= 0;
            font_low <= 0; map_low <= 0; font_bad <= 0; lrc_bad <= 0;
            raw_len <= 0; ptr <= 0; time_stage <= 0;
            time_acc <= 0;
            line_time <= 0; line_base <= 0; text_count <= 0;
            line_len <= 0; utf_code <= 0; utf_left <= 0;
            map_query <= 0; map_index <= 0; map_hit <= 0; map_last <= 0; ptr_finished <= 0;
        end else begin
            font_we <= 0;
            text_we <= 0;
            title_we <= 0;
            cue_we <= 0;
            parse_done <= 0;
            if (start_font) begin
                mode <= MODE_FONT;
                font_ready <= 0;
                font_bad <= 0;
                timing_magic <= 0; timing_char_count <= 0;
                timing_header_ok <= 0; timing_available <= 0; timing_ready <= 0;
            end else if (KARAOKE != 0 && start_timing) begin
                mode <= MODE_TIMING; timing_ready <= 0; timing_received <= 0;
            end else if (start_lrc) begin
                mode <= MODE_LRC;
                lyric_ready <= 0;
                lrc_bad <= 0; timing_ready <= 0;
                raw_len <= 0;
                cue_count <= 0;
                title_count <= 0;
                text_count <= 0;
                line_mode <= L_SEEK;
                utf_left <= 0;
            end else case (mode)
                MODE_FONT: begin
                    if (file_valid) begin
                        case (file_offset)
                            0: if (file_byte != "L") font_bad <= 1;
                            1: if (file_byte != "F") font_bad <= 1;
                            2: if (file_byte != "N") font_bad <= 1;
                            3: if (file_byte != "T") font_bad <= 1;
                            4: if (file_byte != 8'd2) font_bad <= 1;
                            5: map_low <= file_byte;
                            6: if ({file_byte,map_low} == 0 || {file_byte,map_low} > 16'd256) font_bad <= 1;
                            8712: timing_magic[0] <= file_byte == "L";
                            8713: timing_magic[1] <= file_byte == "K";
                            8714: timing_magic[2] <= file_byte == "T";
                            8715: timing_magic[3] <= file_byte == "1";
                            8716: timing_char_count[7:0] <= file_byte;
                            8717: timing_char_count[11:8] <= file_byte[3:0];
                            8718: timing_header_ok <= file_byte == 4;
                            default: ;
                        endcase
                        if (file_offset >= 8 && file_offset < 520) begin
                            if (!file_offset[0]) map_low <= file_byte;
                            else font_map[(file_offset - 8) >> 1] <= {file_byte, map_low};
                        end else if (file_offset >= 520 && file_offset < 8712) begin
                            if (!file_offset[0]) font_low <= file_byte;
                            else begin
                                font_we <= 1;
                                font_addr <= (file_offset - 520) >> 1;
                                font_data <= {file_byte, font_low};
                            end
                        end
                    end
                    if (file_done) begin
                        font_ready <= !font_bad && (file_error == 0);
                        timing_available <= KARAOKE != 0 && &timing_magic &&
                            timing_header_ok && timing_char_count != 0 && timing_char_count <= MAX_TEXT;
                        mode <= MODE_IDLE;
                        parse_done <= 1;
                    end
                end
                MODE_TIMING: begin
                    if (timing_write && timing_write_addr < timing_char_count)
                        timing_received <= timing_received + 1'b1;
                    if (file_done) begin
                        timing_ready <= timing_available && file_error == 0 &&
                            timing_received == timing_char_count && text_count == timing_char_count;
                        mode <= MODE_IDLE; parse_done <= 1;
                    end
                end
                MODE_LRC: begin
                    if (file_valid) begin
                        if (file_offset < 4096) begin
                            raw_len <= file_offset[12:0] + 1'b1;
                        end else lrc_bad <= 1;
                    end
                    if (file_done) begin
                        if (lrc_bad || file_error != 0 || raw_len == 0) begin
                            mode <= MODE_IDLE;
                            parse_done <= 1;
                        end else begin
                            ptr <= 0;
                            pstate <= P_LIMIT;
                            line_mode <= L_SEEK;
                            mode <= MODE_PARSE;
                        end
                    end
                end
                MODE_PARSE: case (pstate)
                    P_LIMIT: begin
                        ptr_finished <= ptr >= raw_len;
                        pstate <= P_FETCH;
                    end
                    P_FETCH: begin
                        if (ptr_finished) begin
                            if (line_mode == L_TEXT && line_len != 0 && cue_count < MAX_CUES) begin
                                cue_we <= 1; cue_index <= cue_count;
                                cue_start <= line_time; cue_base <= line_base;
                                cue_len <= line_len; cue_count <= cue_count + 1'b1;
                            end
                            lyric_ready <= 1;
                            parse_done <= 1;
                            mode <= MODE_IDLE;
                        end else begin
                            pstate <= P_WAIT;
                        end
                    end
                    P_WAIT: pstate <= P_BYTE;
                    P_BYTE: begin
                        ptr <= ptr + 1'b1;
                        pstate <= P_LIMIT;
                        case (line_mode)
                            L_SEEK: if (raw_q == "[") begin
                                line_mode <= L_TIME;
                                time_stage <= 0;
                            end
                            L_SKIP: if (raw_q == 8'h0a) line_mode <= L_SEEK;
                            L_TIME: begin
                                case (time_stage)
                                    0: if (digit) begin time_acc <= digit_value; time_stage <= 1; end
                                       else if (raw_q == "t") time_stage <= 9;
                                       else line_mode <= L_SKIP;
                                    1: if (digit) begin time_acc <= time_step+digit_value; time_stage <= 2; end else line_mode <= L_SKIP;
                                    2: if (raw_q == ":") time_stage <= 3; else line_mode <= L_SKIP;
                                    3: if (digit) begin time_acc <= time_step+digit_value; time_stage <= 4; end else line_mode <= L_SKIP;
                                    4: if (digit) begin time_acc <= time_step+digit_value; time_stage <= 5; end else line_mode <= L_SKIP;
                                    5: if (raw_q == ".") time_stage <= 6; else line_mode <= L_SKIP;
                                    6: if (digit) begin time_acc <= time_step+digit_value; time_stage <= 7; end else line_mode <= L_SKIP;
                                    7: if (digit) begin time_acc <= time_step+digit_value; time_stage <= 8; end else line_mode <= L_SKIP;
                                    8: if (raw_q == "]") begin
                                        line_time <= time_acc;
                                        line_base <= text_count;
                                        line_len <= 0;
                                        line_mode <= L_TEXT;
                                    end else line_mode <= L_SKIP;
                                    9: if (raw_q == "i") time_stage <= 10; else line_mode <= L_SKIP;
                                    10: if (raw_q == ":") begin
                                        title_count <= 0;
                                        utf_left <= 0;
                                        line_mode <= L_TITLE;
                                    end else line_mode <= L_SKIP;
                                    default: line_mode <= L_SKIP;
                                endcase
                            end
                            L_TEXT, L_TITLE: begin
                                if (raw_q == 8'h0a || (line_mode == L_TITLE && raw_q == "]")) begin
                                    if (line_mode == L_TEXT && line_len != 0 && cue_count < MAX_CUES) begin
                                        cue_we <= 1; cue_index <= cue_count;
                                        cue_start <= line_time; cue_base <= line_base;
                                        cue_len <= line_len; cue_count <= cue_count + 1'b1;
                                    end
                                    line_mode <= raw_q == 8'h0a ? L_SEEK : L_SKIP;
                                    utf_left <= 0;
                                end else if (raw_q != 8'h0d &&
                                    ((line_mode == L_TITLE && title_count < 31) ||
                                     (line_mode == L_TEXT && line_len < 31 && text_count < MAX_TEXT))) begin
                                    if (utf_left != 0) begin
                                        if (raw_q[7:6] == 2'b10) begin
                                            utf_code <= {utf_code[9:0], raw_q[5:0]};
                                            utf_left <= utf_left - 1'b1;
                                            if (utf_left == 1) begin
                                                map_query <= {utf_code[9:0], raw_q[5:0]};
                                                map_index <= 0;
                                                pstate <= P_MAP_READ;
                                            end
                                        end else utf_left <= 0;
                                    end else if (raw_q < 8'h80) begin
                                        map_query <= {8'd0,raw_q};
                                        map_index <= 0;
                                        pstate <= P_MAP_READ;
                                    end else if (raw_q[7:5] == 3'b110) begin
                                        utf_code <= {11'd0,raw_q[4:0]};
                                        utf_left <= 1;
                                    end else if (raw_q[7:4] == 4'b1110) begin
                                        utf_code <= {12'd0,raw_q[3:0]};
                                        utf_left <= 2;
                                    end
                                end
                            end
                        endcase
                    end
                    P_MAP_READ: pstate <= P_MAP_CHECK;
                    P_MAP_CHECK: begin
                        // Separate synchronous font RAM comparison from text writes.
                        map_hit <= map_q == map_query;
                        map_last <= map_index == 8'd255;
                        pstate <= P_MAP_EMIT;
                    end
                    P_MAP_EMIT: begin
                        if (map_hit || map_last) begin
                            if (line_mode == L_TITLE) begin
                                title_we <= 1;
                                title_addr <= title_count;
                                title_data <= map_hit ? map_index : 8'd1;
                                title_count <= title_count + 1'b1;
                            end else begin
                                text_we <= 1;
                                text_addr <= text_count;
                                text_data <= map_hit ? map_index : 8'd1;
                                text_count <= text_count + 1'b1;
                                line_len <= line_len + 1'b1;
                            end
                            pstate <= P_LIMIT;
                        end else begin
                            map_index <= map_index + 1'b1;
                            pstate <= P_MAP_READ;
                        end
                    end
                    default: pstate <= P_LIMIT;
                endcase
                default: mode <= MODE_IDLE;
            endcase
        end
    end
endmodule
