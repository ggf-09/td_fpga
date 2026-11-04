`timescale 1ns/1ps

// Owns the shared file streamer before each song starts: loads shared
// FONT.BIN once, or the matching per-track font on each track change, then
// SONGn.LRC. FAT chain walking lives in sd_card_bmp (shared with the cover
// loader and WAV streamer); the WAV owner is held in reset while
// this module owns the streamer.
module runtime_lyric_manager #(
    parameter integer LIBRARY_MODE=0,
    parameter integer CUE_BITS=7, TEXT_BITS=11,
    parameter integer MAX_CUES=126, MAX_TEXT=2048, KARAOKE=0,
    parameter integer FONT_RANGE_READ=0
) (
    input wire clk, rst_n, sd_free,
    input wire timing_clk,
    input wire [11:0] timing_read_addr,
    output wire [7:0] timing_read_data,
    output wire timing_ready,
    input wire [1:0] active_song,
    input wire [3:0] font_bank,
    input wire wav_play_en, wav_file_busy, wav_sector_busy,
    input wire [3:0] lrc_valid,
    input wire [31:0] lrc0_cluster,lrc1_cluster,lrc2_cluster,lrc3_cluster,
    input wire [31:0] lrc0_size,lrc1_size,lrc2_size,lrc3_size,
    input wire font_valid,
    input wire [31:0] font_cluster,font_size,
    output wire ready_for_song,
    output wire lyric_visible,
    // 文件级接口：FAT链遍历由 sd_card_bmp 内共享流读器完成，本模块只发文件描述
    output wire sector_mode,          // =1 时本模块持有共享流读器（owner=1）
    output wire file_start,
    output wire [31:0] file_cluster,
    output wire [31:0] file_size,
    input wire file_done,
    input wire file_valid,
    input wire [7:0] file_byte,
    input wire [31:0] file_offset,
    input wire [7:0] file_error,
    output wire [CUE_BITS-1:0] cue_count,
    output wire font_we,
    output wire [11:0] font_addr,
    output wire [15:0] font_data,
    output wire text_we,
    output wire [TEXT_BITS-1:0] text_addr,
    output wire [7:0] text_data,
    output wire title_we,
    output wire [4:0] title_addr,
    output wire [7:0] title_data,
    output wire [4:0] title_count,
    output wire cue_we,
    output wire [CUE_BITS-1:0] cue_index,
    output wire [15:0] cue_start,
    output wire [TEXT_BITS-1:0] cue_base,
    output wire [4:0] cue_len,
    output wire [31:0] file_start_offset,
    output wire file_partial
);
    localparam [3:0] M_WAIT=0,M_STOP=1,M_FONT_START=2,M_FONT_RUN=3,
                     M_TRACK=4,M_LRC_START=5,M_LRC_RUN=6,M_READY=7,M_TIMING_START=8,M_TIMING_RUN=9;
    reg [3:0] state;
    reg [1:0] target_song;
    reg stream_start, parser_font_start, parser_lrc_start, parser_timing_start;
    wire parser_timing_available;
    reg [31:0] stream_cluster, stream_size;
    reg font_loaded;
    reg [3:0] font_song;
    wire [3:0] active_font_bank=LIBRARY_MODE!=0?font_bank:{2'd0,active_song};
    reg track_has_lrc;
    // 文件流接口别名：字节流来自 sd_card_bmp 内共享流读器（owner=1 时有效）
    wire stream_done = file_done, stream_valid = file_valid;
    wire [7:0] stream_byte = file_byte, stream_error = file_error;
    wire [31:0] stream_offset = file_offset;
    assign file_start = stream_start;
    assign file_cluster = stream_cluster;
    assign file_size = stream_size;
    wire parser_font_ready,parser_lyric_ready,parser_done;
    wire decoder_rst_n;
    reset_sync u_decode_reset (.clk(clk),.ext_rst_n(rst_n),.rst_n_sync(decoder_rst_n));
    wire [31:0] selected_cluster = target_song == 0 ? lrc0_cluster :
                                   target_song == 1 ? lrc1_cluster :
                                   target_song == 2 ? lrc2_cluster : lrc3_cluster;
    wire [31:0] selected_size = target_song == 0 ? lrc0_size :
                                target_song == 1 ? lrc1_size :
                                target_song == 2 ? lrc2_size : lrc3_size;
    wire is_font = state == M_FONT_START || state == M_FONT_RUN ||
                         state == M_TIMING_START || state == M_TIMING_RUN;
    // Optional 64 KiB FONT.BIN: four 16 KiB slots, one 8712-byte LFNT
    // font per track. Only the selected slot is delivered to the decoder.
    wire banked_font = font_size == 32'd65536 || (LIBRARY_MODE!=0 && font_size==32'd262144);
    wire font_bank_valid=font_size!=65536 || active_font_bank<4;
    wire ranged_font = FONT_RANGE_READ != 0 && banked_font;
    assign file_partial = ranged_font && is_font;
    assign file_start_offset = !file_partial ? 32'd0 :
        state == M_TIMING_START || state == M_TIMING_RUN ?
        {14'd0,font_song,14'd9216} : {14'd0,font_song,14'd0};
    wire selected_font_byte = stream_offset[31:14] == {14'd0,font_song};
    assign sector_mode = state == M_FONT_START || state == M_FONT_RUN ||
                         state == M_LRC_START || state == M_LRC_RUN ||
                         state == M_TIMING_START || state == M_TIMING_RUN;
    assign ready_for_song = state == M_READY && active_song == target_song &&
                            (!banked_font || !font_loaded || font_song==active_font_bank);
    assign lyric_visible = ready_for_song && track_has_lrc &&
                           parser_lyric_ready && font_loaded;

    // Register the bank/offset selection before the decoder RAM ports.
    // Valid, byte, offset, completion and error travel through one stage.
    reg decode_valid,decode_done;
    reg [7:0] decode_byte,decode_error;
    reg [31:0] decode_offset;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            decode_valid<=0;decode_done<=0;decode_byte<=0;decode_error<=0;decode_offset<=0;
        end else begin
            decode_valid<=stream_valid && (!is_font || !banked_font || FONT_RANGE_READ != 0 || selected_font_byte);
            decode_offset<=is_font && banked_font ? {18'd0,stream_offset[13:0]} : stream_offset;
            decode_byte<=stream_byte;decode_done<=stream_done;decode_error<=stream_error;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= M_WAIT; target_song <= 0;
            stream_start <= 0; parser_font_start <= 0;
            stream_cluster <= 0; stream_size <= 0;
            parser_lrc_start <= 0; parser_timing_start <= 0; font_loaded <= 0;
            font_song <= 0;
            track_has_lrc <= 0;
        end else begin
            stream_start <= 0;
            parser_font_start <= 0;
            parser_lrc_start <= 0; parser_timing_start <= 0;
            if (!sd_free) begin
                state <= M_WAIT;
                font_loaded <= 0;
            end else case (state)
                M_WAIT: state <= M_STOP;
                M_STOP: if (!wav_play_en && !wav_file_busy && !wav_sector_busy)
                            if ((!font_loaded || (banked_font && font_song != active_font_bank)) &&
                                font_valid && font_bank_valid && (font_size == 8712 || banked_font)) begin
                                font_song <= active_font_bank;
                                state <= M_FONT_START;
                            end
                            else begin
                                if(!font_valid || !font_bank_valid)font_loaded<=0;
                                state <= M_TRACK;
                            end
                M_FONT_START: begin
                    stream_cluster <= font_cluster;
                    stream_size <= ranged_font ? {14'd0,font_song,14'd9216} : font_size;
                    stream_start <= 1;
                    parser_font_start <= 1;
                    state <= M_FONT_RUN;
                end
                M_FONT_RUN: if (parser_done) begin
                    font_loaded <= parser_font_ready;
                    state <= M_TRACK;
                end
                M_TRACK: begin
                    target_song <= active_song;
                    if (banked_font && font_loaded && font_song != active_font_bank) begin
                        state <= M_STOP;
                    end else if (font_loaded && lrc_valid[active_song] &&
                        (active_song == 0 ? lrc0_size : active_song == 1 ? lrc1_size :
                         active_song == 2 ? lrc2_size : lrc3_size) <= 4096) begin
                        track_has_lrc <= 1;
                        state <= M_LRC_START;
                    end else begin
                        track_has_lrc <= 0;
                        state <= M_READY;
                    end
                end
                M_LRC_START: begin
                    stream_cluster <= selected_cluster;
                    stream_size <= selected_size;
                    stream_start <= 1;
                    parser_lrc_start <= 1;
                    state <= M_LRC_RUN;
                end
                M_LRC_RUN: if (parser_done) begin
                    if (KARAOKE != 0 && parser_timing_available && parser_lyric_ready)
                        state <= M_TIMING_START;
                    else state <= M_READY;
                end
                M_TIMING_START: begin
                    stream_cluster <= font_cluster;
                    stream_size <= ranged_font ? {14'd0,font_song,14'd12288} : font_size;
                    stream_start <= 1; parser_timing_start <= 1;
                    state <= M_TIMING_RUN;
                end
                M_TIMING_RUN: if (parser_done) state <= M_READY;
                M_READY: if (active_song != target_song ||
                    (banked_font && font_loaded && font_song!=active_font_bank)) state <= M_STOP;
                default: state <= M_WAIT;
            endcase
        end
    end

    fat_lrc_loader #(.CUE_BITS(CUE_BITS),.TEXT_BITS(TEXT_BITS),
        .MAX_CUES(MAX_CUES),.MAX_TEXT(MAX_TEXT),.KARAOKE(KARAOKE)) u_lrc_decode (
        .clk(clk),.rst_n(decoder_rst_n),
        .start_font(parser_font_start),.start_lrc(parser_lrc_start),
        .start_timing(parser_timing_start),.timing_clk(timing_clk),
        .timing_read_addr(timing_read_addr),.timing_read_data(timing_read_data),
        .timing_available(parser_timing_available),.timing_ready(timing_ready),
        .file_valid(decode_valid),.file_byte(decode_byte),.file_offset(decode_offset),
        .file_done(decode_done),
        .file_error(decode_error),.font_ready(parser_font_ready),
        .lyric_ready(parser_lyric_ready),.parse_done(parser_done),
        .cue_count(cue_count),.font_we(font_we),
        .font_addr(font_addr),.font_data(font_data),
        .text_we(text_we),.text_addr(text_addr),
        .text_data(text_data),.cue_we(cue_we),
        .title_we(title_we),.title_addr(title_addr),
        .title_data(title_data),.title_count(title_count),
        .cue_index(cue_index),.cue_start(cue_start),
        .cue_base(cue_base),.cue_len(cue_len)
    );
endmodule
