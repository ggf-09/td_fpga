`timescale 1ns/1ps

// Runtime LRC subtitles. Timing/text arrive from the FAT reader; bitmap font
// rows arrive from FONT.BIN. All writes finish before ready_sd is asserted.
module runtime_lyric_overlay #(
    parameter integer LYRIC_Y = 376,
    parameter integer TITLE_Y = 56,
    parameter integer H_ACT = 640,
    parameter integer CUE_BITS=7, TEXT_BITS=11,
    parameter integer CUE_STORAGE=(1<<CUE_BITS), TEXT_DEPTH=2048
) (
    input wire clk, rst_n, vsync, de,
    input wire [23:0] rgb_in,
    input wire [9:0] pixel_x,
    input wire enable,
    input wire [15:0] play_cs,
    input wire sd_clk,
    input wire ready_sd,
    input wire [CUE_BITS-1:0] cue_count_sd,
    input wire cue_we,
    input wire [CUE_BITS-1:0] cue_index,
    input wire [15:0] cue_start,
    input wire [TEXT_BITS-1:0] cue_base,
    input wire [4:0] cue_len,
    input wire text_we,
    input wire [TEXT_BITS-1:0] text_addr,
    input wire [7:0] text_data,
    input wire font_we,
    input wire [11:0] font_addr,
    input wire [15:0] font_data,
    // Glyph indices use the same card-loaded FONT.BIN as the subtitle. The
    // writer keeps them stable while title_ready_sd is high. This handshake
    // is independent of ready_sd: a title does not require timed lyrics.
    input wire title_we,
    input wire [4:0] title_addr,
    input wire [7:0] title_data,
    input wire [4:0] title_count_sd,
    input wire title_ready_sd,
    output wire [23:0] rgb_out,
    output wire lyric_active
);
    localparam integer MAXCNT=31;
    reg [15:0] cue_time [0:CUE_STORAGE-1];
    // A single 17-bit metadata word fits the RAM's 18-bit port. Keeping
    // offset and length together avoids two separately inferred blocks.
    reg [TEXT_BITS+4:0] cue_meta [0:CUE_STORAGE-1];
    reg [15:0] glyph_mem [0:4095];
    reg [7:0] title_ids [0:MAXCNT-1];
    always @(posedge sd_clk) begin
        if (cue_we) begin
            cue_time[cue_index] <= cue_start;
            cue_meta[cue_index] <= {cue_len,cue_base};
        end
        if (font_we) glyph_mem[font_addr] <= font_data;
        if (title_we && title_addr < MAXCNT) title_ids[title_addr] <= title_data;
    end

    reg ready1, ready2;
    reg title_ready1, title_ready2;
    reg [4:0] title_count_pix;
    // Keep the loaded song title visible after ordered playback stops; the
    // subtitle below still follows the WAV enable and its time window.
    wire has_title = title_ready2 && title_count_pix != 0;
    reg [CUE_BITS-1:0] cue_count_pix;
    reg [CUE_BITS-1:0] cue_cursor;
    reg vs_q, de_q;
    reg [11:0] line_y;
    wire [CUE_BITS-1:0] next_cue = cue_cursor + 1'b1;
    reg [15:0] active_start, next_start;
    reg [TEXT_BITS+4:0] char_meta;
    wire [TEXT_BITS-1:0] char_offset = char_meta[TEXT_BITS-1:0];
    wire [4:0] char_count = char_meta[TEXT_BITS+4:TEXT_BITS];
    reg [CUE_BITS-1:0] meta_cursor;
    // Read stable subtitle metadata into the video clock domain. The ready
    // handshake keeps the SD writer idle throughout playback.
    always @(posedge clk) begin
        active_start <= cue_time[cue_cursor];
        next_start <= cue_time[next_cue];
        char_meta <= cue_meta[cue_cursor];
        meta_cursor <= cue_cursor;
    end
    wire [16:0] active_end = (next_cue < cue_count_pix) ? {1'b0,next_start} :
                             {1'b0,active_start} + 17'd800;
    wire has_lyric = enable && ready2 && meta_cursor == cue_cursor && cue_count_pix != 0 &&
                     play_cs >= active_start && play_cs < active_end;

    reg [7:0] glyph_ids [0:MAXCNT-1];
    reg [1:0] cache_state;
    reg [CUE_BITS-1:0] cache_cursor;
    reg cache_valid;
    reg [4:0] cache_i, cache_count;
    reg [TEXT_BITS-1:0] cache_addr;
    reg [7:0] char_q;
    localparam C_IDLE=0, C_READ=1, C_STORE=2;
    generate if(TEXT_BITS>11) begin:g_large_text
        // Separate 2 KiB + 1 KiB banks avoid rounding a 3 KiB array to
        // four 9K blocks. Read both banks and pipeline the address tag.
        reg [7:0] text_lo[0:2047];
        reg [7:0] text_hi[0:1023];
        reg [7:0] lo_q,hi_q;
        reg bank_q;
        always @(posedge sd_clk) if(text_we) begin
            if(text_addr[11])text_hi[text_addr[9:0]]<=text_data;
            else text_lo[text_addr[10:0]]<=text_data;
        end
        always @(posedge clk) begin
            lo_q<=text_lo[cache_addr[10:0]];
            hi_q<=text_hi[cache_addr[9:0]];
            bank_q<=cache_addr[11];
        end
        always @* char_q=bank_q?hi_q:lo_q;
    end else begin:g_legacy_text
        reg [7:0] text_mem[0:TEXT_DEPTH-1];
        always @(posedge sd_clk)if(text_we)text_mem[text_addr]<=text_data;
        always @(posedge clk)char_q<=text_mem[cache_addr];
    end endgenerate

    reg ld_state;
    reg ld_title, buf_title;
    reg [5:0] ld_cnt, ld_total;
    reg [4:0] ld_cmax;
    reg [3:0] ld_row;
    reg [4:0] d_ci;
    reg d_half;
    reg [3:0] buf_row;
    reg buf_valid;
    reg [15:0] glyph_q;
    wire ld_half = ld_cnt >= {1'b0,ld_cmax};
    wire [4:0] ld_ci = ld_half ? ld_cnt[4:0]-ld_cmax : ld_cnt[4:0];
    wire [3:0] ld_rrow = ld_half ? ld_row-1'b1 : ld_row;
    wire [7:0] ld_cidx = ld_title ? title_ids[ld_ci] : glyph_ids[ld_ci];
    wire [11:0] glyph_addr = {ld_cidx,ld_rrow};
    always @(posedge clk) if (ld_state && ld_cnt < ld_total)
        glyph_q <= glyph_mem[glyph_addr];

    reg [15:0] line_ff0 [0:MAXCNT-1];
    reg [15:0] line_ff1 [0:MAXCNT-1];
    wire [11:0] y_next = line_y + 1'b1;
    wire lyric_pre_kick = de_q && !de && has_lyric && cache_valid &&
                    cache_cursor == cue_cursor &&
                    y_next >= LYRIC_Y[11:0] && y_next < LYRIC_Y[11:0]+16;
    wire title_pre_kick = de_q && !de && has_title &&
                    y_next >= TITLE_Y[11:0] && y_next < TITLE_Y[11:0]+16;
    wire pre_kick = lyric_pre_kick || title_pre_kick;
    wire [3:0] kick_row = title_pre_kick ? y_next - TITLE_Y[11:0] :
                                                         y_next - LYRIC_Y[11:0];
    wire [11:0] row12 = line_y - (buf_title ? TITLE_Y[11:0] : LYRIC_Y[11:0]);
    wire in_lyric = !buf_title && has_lyric && buf_valid && de &&
                    line_y >= LYRIC_Y[11:0] && line_y < LYRIC_Y[11:0]+16 &&
                    buf_row == row12[3:0];
    wire in_title = buf_title && has_title && buf_valid && de &&
                    line_y >= TITLE_Y[11:0] && line_y < TITLE_Y[11:0]+16 &&
                    buf_row == row12[3:0];
    wire [4:0] render_count = buf_title ? title_count_pix : char_count;
    wire [9:0] text_w = {5'd0,render_count,4'b0}+{7'd0,render_count,1'b0};
    wire [9:0] start_x = (H_ACT-text_w) >> 1;
    wire in_txt = (in_lyric || in_title) && pixel_x >= start_x && pixel_x < start_x+text_w;
    reg [4:0] char_i, col_cnt;
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready1 <= 0; ready2 <= 0; cue_cursor <= 0;
            title_ready1 <= 0; title_ready2 <= 0; title_count_pix <= 0;
            cue_count_pix <= 0;
            vs_q <= 1; de_q <= 0; line_y <= 0;
            cache_state <= C_IDLE; cache_cursor <= 0;
            cache_valid <= 0; cache_i <= 0; cache_count <= 0;
            cache_addr <= 0; ld_state <= 0; ld_cnt <= 0;
            ld_title <= 0; buf_title <= 0;
            ld_total <= 0; ld_cmax <= 0; ld_row <= 0;
            d_ci <= 0; d_half <= 0; buf_row <= 15;
            buf_valid <= 0; char_i <= 0; col_cnt <= 0;
            for (k=0;k<MAXCNT;k=k+1) begin
                glyph_ids[k] <= 0; line_ff0[k] <= 0; line_ff1[k] <= 0;
            end
        end else begin
            ready1 <= ready_sd; ready2 <= ready1;
            // Unconnected new ports in older integrations are treated as
            // disabled in simulation, while hardware remains a normal CDC.
            if (title_ready_sd == 1'b1) title_ready1 <= 1'b1;
            else title_ready1 <= 1'b0;
            title_ready2 <= title_ready1;
            if (title_ready1 && !title_ready2) title_count_pix <= title_count_sd;
            if (!title_ready2 && buf_title) buf_valid <= 0;
            if (ready1 && !ready2) cue_count_pix <= cue_count_sd;
            vs_q <= vsync; de_q <= de;
            if (!vsync) line_y <= 0;
            else if (de_q && !de) line_y <= line_y + 1'b1;
            if (!ready2) begin
                cue_cursor <= 0; cache_valid <= 0;
                cache_state <= C_IDLE;
                if (!buf_title) buf_valid <= 0;
            end else if (!vsync && vs_q) begin
                if (play_cs == 0) cue_cursor <= 0;
                else if (next_cue < cue_count_pix && play_cs >= next_start)
                    cue_cursor <= next_cue;
            end

            if (ready2) case (cache_state)
                C_IDLE: if (has_lyric && (!cache_valid || cache_cursor != cue_cursor)) begin
                    cache_valid <= 0;
                    if (!buf_title) buf_valid <= 0;
                    cache_cursor <= cue_cursor;
                    cache_count <= char_count;
                    cache_addr <= char_offset;
                    cache_i <= 0;
                    cache_state <= C_READ;
                end
                C_READ: cache_state <= C_STORE;
                C_STORE: begin
                    glyph_ids[cache_i] <= char_q;
                    if (cache_i + 1'b1 >= cache_count) begin
                        cache_valid <= 1;
                        cache_state <= C_IDLE;
                    end else begin
                        cache_i <= cache_i + 1'b1;
                        cache_addr <= cache_addr + 1'b1;
                        cache_state <= C_READ;
                    end
                end
                default: cache_state <= C_IDLE;
            endcase

            if (!ld_state) begin
                if (pre_kick) begin
                    ld_state <= 1;
                    ld_title <= title_pre_kick;
                    ld_cnt <= 0;
                    ld_row <= kick_row;
                    ld_cmax <= title_pre_kick ? title_count_pix : char_count;
                    ld_total <= kick_row == 0 ?
                        {1'b0,(title_pre_kick ? title_count_pix : char_count)} :
                        ({1'b0,(title_pre_kick ? title_count_pix : char_count)} << 1);
                end
            end else begin
                if (ld_cnt != 0) begin
                    if (d_half) line_ff1[d_ci] <= glyph_q;
                    else line_ff0[d_ci] <= glyph_q;
                end
                if (ld_cnt == ld_total) begin
                    buf_row <= ld_row; buf_valid <= 1; buf_title <= ld_title;
                    ld_state <= 0; ld_cnt <= 0;
                end else begin
                    d_ci <= ld_ci;
                    d_half <= ld_half;
                    ld_cnt <= ld_cnt + 1'b1;
                end
            end

            if (!in_txt) begin char_i <= 0; col_cnt <= 0; end
            else if (col_cnt == 17) begin col_cnt <= 0; char_i <= char_i+1'b1; end
            else col_cnt <= col_cnt+1'b1;
        end
    end
    wire [15:0] cur_g = line_ff0[char_i];
    wire [15:0] prev_g = line_ff1[char_i];
    wire [3:0] bitidx = 4'd15-col_cnt[3:0];
    wire txt_p = in_txt && col_cnt < 16 && char_i < render_count && cur_g[bitidx];
    wire sh_p = in_txt && col_cnt > 0 && col_cnt < 16 && char_i < render_count &&
                row12[3:0] != 0 && prev_g[bitidx+1'b1];
    assign lyric_active = txt_p || sh_p;
    assign rgb_out = txt_p ? 24'hffe000 : sh_p ? 24'h000000 : rgb_in;
endmodule


// Three-line lyric window. Metadata has one video read port; a four-bank
// ring cache keeps previous/current/next text and timing without tripling
// glyph RAM. The raw UTF-8 RAM in the loader is reused for timing playback.
module scrolling_lyric_overlay #(
    parameter integer LYRIC_Y=344, TITLE_Y=56, H_ACT=640, LINE_GAP=24,
    parameter integer CUE_BITS=8,TEXT_BITS=12,CUE_STORAGE=160,TEXT_DEPTH=3072
)(
    input wire clk,rst_n,vsync,de,
    input wire [23:0] rgb_in,
    input wire [9:0] pixel_x,
    input wire enable,
    input wire [1:0] panel_alpha,
    input wire [2:0] panel_position,
    input wire [15:0] play_cs,
    input wire sd_clk,ready_sd,
    input wire [CUE_BITS-1:0] cue_count_sd,
    input wire cue_we,
    input wire [CUE_BITS-1:0] cue_index,
    input wire [15:0] cue_start,
    input wire [TEXT_BITS-1:0] cue_base,
    input wire [4:0] cue_len,
    input wire text_we,
    input wire [TEXT_BITS-1:0] text_addr,
    input wire [7:0] text_data,
    input wire font_we,
    input wire [11:0] font_addr,
    input wire [15:0] font_data,
    input wire title_we,
    input wire [4:0] title_addr,
    input wire [7:0] title_data,
    input wire [4:0] title_count_sd,
    input wire title_ready_sd,
    input wire timing_ready_sd,
    output wire [11:0] timing_read_addr,
    input wire [7:0] timing_read_data,
    output wire [23:0] rgb_out,
    output wire lyric_active
);
    localparam META_W=16+TEXT_BITS+5;
    reg [META_W-1:0] cue_ram[0:CUE_STORAGE-1];
    // glyph_mem[0:4095] 已迁 BRAM32K（u_glyph_ram，见下方 ld 信号区实例化）
    reg [7:0] title_ids[0:30];
    always @(posedge sd_clk) begin
        if(cue_we)cue_ram[cue_index]<={cue_start,cue_base,cue_len};
        if(title_we && title_addr<31)title_ids[title_addr]<=title_data;
    end
    reg ready1,ready2,tr1,tr2,title1,title2;
    reg [4:0] title_count;
    reg [CUE_BITS-1:0] cue_count,cue_cursor;
    wire [CUE_BITS-1:0] prev_cue=cue_cursor-1'b1,next_cue=cue_cursor+1'b1;
    wire [1:0] cur_bank=cue_cursor[1:0],prev_bank=prev_cue[1:0],next_bank=next_cue[1:0];
    reg [3:0] cache_valid;
    reg [CUE_BITS-1:0] cache_tag[0:3];
    reg [15:0] cache_start[0:3];
    reg [4:0] cache_count[0:3];
    // Asynchronous small distributed memory; no reset on payload arrays.
    reg [15:0] cache_text[0:127];
    wire cur_ok=cache_valid[cur_bank] && cache_tag[cur_bank]==cue_cursor;
    wire prev_ok=cue_cursor!=0 && cache_valid[prev_bank] && cache_tag[prev_bank]==prev_cue;
    wire next_ok=next_cue<cue_count && cache_valid[next_bank] && cache_tag[next_bank]==next_cue;
    reg [CUE_BITS-1:0] meta_addr,load_cue;
    reg [META_W-1:0] meta_q;
    always @(posedge clk) meta_q<=cue_ram[meta_addr];
    reg [2:0] fill_state;
    localparam F_IDLE=0,F_META_WAIT=1,F_META=2,F_WAIT=3,F_STORE=4,
               F_SEEK_ADDR=5,F_SEEK_WAIT=6,F_SEEK_COMPARE=7;
    reg [15:0] play_cs_q,seek_cs;
    reg [CUE_BITS-1:0] seek_index;
    wire time_jump=play_cs<play_cs_q || {1'b0,play_cs}>{1'b0,play_cs_q}+17'd2;
    reg [4:0] fill_i,fill_count;
    reg [TEXT_BITS-1:0] cache_addr;
    wire [1:0] fill_bank=load_cue[1:0];
    assign timing_read_addr=cache_addr;
    reg [7:0] char_q;
    generate if(TEXT_BITS>11)begin:g_large_text
        // text_lo[2048]+text_hi[1024] 合并迁 BRAM32K（u_text_ram）：写 sd_clk，读 clk。
        // 原结构为"寄存读+组合bank选择"，BRAM32K 同步读输出等价，保持一拍延迟。
        wire [7:0] text_ram_q;
        ram32k_dp8 u_text_ram (
            .clka(sd_clk), .wea(text_we), .addra(text_addr), .dia(text_data), .doa(),
            .clkb(clk), .addrb(cache_addr), .dob(text_ram_q)
        );
        always @* char_q=text_ram_q;
    end else begin:g_small_text
        reg [7:0] text_mem[0:TEXT_DEPTH-1];
        always @(posedge sd_clk)if(text_we)text_mem[text_addr]<=text_data;
        always @(posedge clk)char_q<=text_mem[cache_addr];
    end endgenerate

    reg vs_q,de_q;
    reg [11:0] line_y;
    reg [4:0] scroll_offset;
    wire frame_tick=!vsync && vs_q;
    wire show_lyrics=enable && ready2 && cue_count!=0 && cur_ok;
    wire [11:0] y_next=line_y+1'b1;
    wire has_title=title2 && title_count!=0;
    // Stable video-domain controls, latched only during frame blanking.
    // Default parameters keep legacy integrations without the new inputs valid.
    reg [1:0] panel_alpha_q;
    reg [2:0] panel_position_q;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin panel_alpha_q<=1;panel_position_q<=7;end
        else if(frame_tick)begin
            case(panel_alpha)
                0,1,2,3:panel_alpha_q<=panel_alpha;
                default:panel_alpha_q<=1;
            endcase
            case(panel_position)
                0,1,2,3,4,5,6,7:panel_position_q<=panel_position;
                default:panel_position_q<=7;
            endcase
        end
    end
    // Move in 32-pixel increments. Only the high raster bits need addition.
    // Position 7 preserves the old y312..399 panel; position 0 is y88..175.
    wire [6:0] lyric_band=line_y[11:5]+{4'd0,~panel_position_q};
    wire [6:0] lyric_next_band=y_next[11:5]+{4'd0,~panel_position_q};
    wire [11:0] lyric_line_y={lyric_band,line_y[4:0]};
    wire [11:0] lyric_y_next={lyric_next_band,y_next[4:0]};
    wire [11:0] prev_y=LYRIC_Y-LINE_GAP+scroll_offset;
    wire [11:0] current_y=LYRIC_Y+scroll_offset;
    wire [11:0] next_y=LYRIC_Y+LINE_GAP+scroll_offset;

    reg kick,kick_title;
    reg [1:0] kick_bank,kick_style;
    reg [3:0] kick_row;
    reg [4:0] kick_count;
    reg [15:0] kick_start;
    always @* begin
        kick=0;kick_title=0;kick_bank=0;kick_style=0;kick_row=0;kick_count=0;kick_start=0;
        if(de_q && !de)begin
            if(has_title && y_next>=TITLE_Y && y_next<TITLE_Y+16)begin
                kick=1;kick_title=1;kick_row=y_next-TITLE_Y;kick_count=title_count;
            end else if(show_lyrics && lyric_y_next>=LYRIC_Y-LINE_GAP-8 && lyric_y_next<400)begin
                if(prev_ok && lyric_y_next>=prev_y && lyric_y_next<prev_y+16)begin
                    kick=1;kick_bank=prev_bank;kick_style=0;kick_row=lyric_y_next-prev_y;
                end else if(lyric_y_next>=current_y && lyric_y_next<current_y+16)begin
                    kick=1;kick_bank=cur_bank;kick_style=1;kick_row=lyric_y_next-current_y;
                end else if(next_ok && lyric_y_next>=next_y && lyric_y_next<next_y+16)begin
                    kick=1;kick_bank=next_bank;kick_style=2;kick_row=lyric_y_next-next_y;
                end
                kick_count=cache_count[kick_bank];kick_start=cache_start[kick_bank];
            end
        end
    end
    reg ld_state,ld_title,buf_title,buf_valid;
    reg [1:0] ld_bank,ld_style,buf_style;
    reg [4:0] ld_count,buf_count;
    reg [15:0] ld_start,buf_start;
    reg [3:0] ld_row,buf_row;
    reg [11:0] ld_y,buf_y;
    reg [5:0] ld_cnt,ld_total;
    wire ld_half=ld_cnt>={1'b0,ld_count};
    wire [4:0] ld_ci=ld_half?ld_cnt[4:0]-ld_count:ld_cnt[4:0];
    wire [3:0] ld_rrow=ld_half?ld_row-1'b1:ld_row;
    wire [15:0] ld_pair=cache_text[{ld_bank,ld_ci}];
    wire [7:0] ld_gid=ld_title?title_ids[ld_ci]:ld_pair[7:0];
    // 字形缓存：BRAM32K，A口(sd_clk)写字库，B口(clk)行填充读；同步读与原推断RAM逐拍等价
    wire [15:0] glyph_q;
    ram32k_dp16 u_glyph_ram (
        .clka(sd_clk), .wea(font_we), .addra(font_addr), .dia(font_data),
        .clkb(clk), .addrb({ld_gid,ld_rrow}), .dob(glyph_q)
    );
    reg [7:0] tick_q;
    always @(posedge clk)if(ld_state && ld_cnt<ld_total)begin
        tick_q<=ld_pair[15:8];
    end
    reg [15:0] line_ff0[0:30],line_ff1[0:30];
    reg [7:0] line_tick[0:30];
    reg [4:0] d_ci;
    reg d_half;
    wire [9:0] text_w={5'd0,buf_count,4'b0}+{7'd0,buf_count,1'b0};
    wire [9:0] start_x=(H_ACT-text_w)>>1;
    wire row_visible=buf_title?has_title:show_lyrics;
    wire in_txt=row_visible && buf_valid && de && line_y==buf_y &&
                pixel_x>=start_x && pixel_x<start_x+text_w;
    reg [4:0] char_i,col_cnt;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            play_cs_q<=0;seek_cs<=0;seek_index<=0;
            ready1<=0;ready2<=0;tr1<=0;tr2<=0;title1<=0;title2<=0;title_count<=0;
            cue_count<=0;cue_cursor<=0;cache_valid<=0;
            meta_addr<=0;load_cue<=0;fill_state<=F_IDLE;fill_i<=0;fill_count<=0;cache_addr<=0;
            vs_q<=1;de_q<=0;line_y<=0;scroll_offset<=0;
            ld_state<=0;ld_title<=0;ld_bank<=0;ld_style<=0;ld_count<=0;ld_start<=0;ld_row<=0;ld_y<=0;
            ld_cnt<=0;ld_total<=0;d_ci<=0;d_half<=0;
            buf_title<=0;buf_valid<=0;buf_style<=0;buf_count<=0;buf_start<=0;buf_row<=0;buf_y<=0;
            char_i<=0;col_cnt<=0;
        end else begin
            play_cs_q<=play_cs;
            ready1<=ready_sd;ready2<=ready1;tr1<=timing_ready_sd;tr2<=tr1;
            title1<=title_ready_sd;title2<=title1;
            if(title1 && !title2)title_count<=title_count_sd;
            if(ready1 && !ready2)cue_count<=cue_count_sd;
            vs_q<=vsync;de_q<=de;
            if(!vsync)line_y<=0;else if(de_q && !de)line_y<=line_y+1'b1;
            if(!ready2)begin
                cue_cursor<=0;cache_valid<=0;fill_state<=F_IDLE;scroll_offset<=0;
                if(!buf_title)buf_valid<=0;
            end else begin
                if(frame_tick && fill_state<F_SEEK_ADDR)begin
                    if(play_cs==0)begin cue_cursor<=0;scroll_offset<=0;end
                    else if(next_ok && play_cs>=cache_start[next_bank])begin
                        cue_cursor<=next_cue;scroll_offset<=LINE_GAP;
                    end else if(scroll_offset>=2)scroll_offset<=scroll_offset-2;
                    else scroll_offset<=0;
                end
                case(fill_state)
                    F_IDLE:begin
                        if(cue_count!=0 && !cur_ok)begin
                            load_cue<=cue_cursor;meta_addr<=cue_cursor;fill_state<=F_META_WAIT;
                        end else if(next_cue<cue_count && !next_ok)begin
                            load_cue<=next_cue;meta_addr<=next_cue;fill_state<=F_META_WAIT;
                        end else if(cue_cursor!=0 && !prev_ok)begin
                            load_cue<=prev_cue;meta_addr<=prev_cue;fill_state<=F_META_WAIT;
                        end
                    end
                    F_META_WAIT:fill_state<=F_META;
                    F_META:begin
                        cache_tag[fill_bank]<=load_cue;cache_valid[fill_bank]<=0;
                        cache_start[fill_bank]<=meta_q[META_W-1:TEXT_BITS+5];
                        cache_count[fill_bank]<=meta_q[4:0];fill_count<=meta_q[4:0];
                        fill_i<=0;cache_addr<=meta_q[TEXT_BITS+4:5];
                        if(meta_q[4:0]==0)begin cache_valid[fill_bank]<=1;fill_state<=F_IDLE;end
                        else fill_state<=F_WAIT;
                    end
                    F_WAIT:fill_state<=F_STORE;
                    F_STORE:begin
                        cache_text[{fill_bank,fill_i}]<={timing_read_data,char_q};
                        if(fill_i+1'b1>=fill_count)begin cache_valid[fill_bank]<=1;fill_state<=F_IDLE;end
                        else begin fill_i<=fill_i+1'b1;cache_addr<=cache_addr+1'b1;fill_state<=F_WAIT;end
                    end
                    // A bounded metadata scan finishes in <20us at 25MHz for
                    // 158 cues; it reuses the existing RAM port and is unrelated
                    // to video frame timing. Smaller than binary-search hardware.
                    F_SEEK_ADDR:begin meta_addr<=seek_index;fill_state<=F_SEEK_WAIT;end
                    F_SEEK_WAIT:fill_state<=F_SEEK_COMPARE;
                    F_SEEK_COMPARE:begin
                        if(meta_q[META_W-1:TEXT_BITS+5]>seek_cs)begin
                            cue_cursor<=seek_index==0?0:seek_index-1'b1;fill_state<=F_IDLE;
                        end else if(seek_index+1'b1>=cue_count)begin
                            cue_cursor<=seek_index;fill_state<=F_IDLE;
                        end else begin seek_index<=seek_index+1'b1;fill_state<=F_SEEK_ADDR;end
                    end
                    default:fill_state<=F_IDLE;
                endcase
                if(time_jump && cue_count!=0)begin
                    seek_cs<=play_cs;seek_index<=0;
                    cache_valid<=0;buf_valid<=0;scroll_offset<=0;fill_state<=F_SEEK_ADDR;
                end
            end
            if(!ld_state)begin
                if(kick && kick_count!=0)begin
                    ld_state<=1;ld_title<=kick_title;ld_bank<=kick_bank;ld_style<=kick_style;
                    ld_count<=kick_count;ld_start<=kick_start;ld_row<=kick_row;ld_y<=y_next;
                    ld_cnt<=0;ld_total<=kick_row==0?{1'b0,kick_count}:({1'b0,kick_count}<<1);
                end
            end else begin
                if(ld_cnt!=0)begin
                    if(d_half)line_ff1[d_ci]<=glyph_q;
                    else begin line_ff0[d_ci]<=glyph_q;line_tick[d_ci]<=tick_q;end
                end
                if(ld_cnt==ld_total)begin
                    buf_valid<=1;buf_title<=ld_title;buf_style<=ld_style;buf_count<=ld_count;
                    buf_start<=ld_start;buf_row<=ld_row;buf_y<=ld_y;ld_state<=0;ld_cnt<=0;
                end else begin d_ci<=ld_ci;d_half<=ld_half;ld_cnt<=ld_cnt+1'b1;end
            end
            if(frame_tick && panel_position!=panel_position_q)buf_valid<=0;
            if(!in_txt)begin char_i<=0;col_cnt<=0;end
            else if(col_cnt==17)begin col_cnt<=0;char_i<=char_i+1'b1;end
            else col_cnt<=col_cnt+1'b1;
        end
    end
    wire [15:0] glyph=line_ff0[char_i],shadow=line_ff1[char_i];
    wire [3:0] bitidx=4'd15-col_cnt[3:0];
    wire txt_p=in_txt && col_cnt<16 && char_i<buf_count && glyph[bitidx];
    wire sh_p=in_txt && col_cnt>0 && col_cnt<16 && char_i<buf_count && buf_row!=0 && shadow[bitidx+1'b1];
    wire [16:0] char_start={1'b0,buf_start}+{7'd0,line_tick[char_i],2'b00};
    wire highlighted=!tr2 || {1'b0,play_cs}>=char_start;
    wire [23:0] text_color=buf_title?24'hffe000:
        buf_style==1?(highlighted?24'hffe000:24'hffffff):24'hb0b8c8;
    wire panel=show_lyrics && de && pixel_x>=32 && pixel_x<608 &&
        lyric_line_y>=LYRIC_Y-LINE_GAP-8 && lyric_line_y<400;
    reg [23:0] panel_rgb;
    always @* case(panel_alpha_q)
        0:panel_rgb=24'h000000;
        1:panel_rgb={2'b00,rgb_in[23:18],2'b00,rgb_in[15:10],2'b00,rgb_in[7:2]};
        2:panel_rgb={1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
        default:panel_rgb=rgb_in;
    endcase
    wire [23:0] background=panel?panel_rgb:rgb_in;
    assign lyric_active=txt_p || sh_p;
    assign rgb_out=txt_p?text_color:sh_p?24'h000000:background;
endmodule
