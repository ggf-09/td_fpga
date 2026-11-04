`timescale 1ns/1ps

// 第16课扩展：歌词叠加（KTV单行居中，硬编码字形ROM，参照topic1字幕条的硬编码模式）
// 《反方向的钟》前100s：15行歌词、91个去重汉字(含空格)、16x16宋体点阵
// 数据文件（均由 doc/convert/lyric_gen.py 自动生成，勿手改）：
//   lyric_table.vh       — 行表/字索引流 case函数（本文件include）
//   lyric_glyph_b0..3.mif— 4块9K BRAM初始化（512×18bit，Altera标准MIF）
// 架构（行缓冲预读，显示零延迟，无BRAM读对齐问题）：
//   歌词区16个显示行，每行row在上一行消隐期把「本行row + 上一行row-1」两组字形行
//   （各≤14字×16bit）从BRAM同步读（1拍流水，≤29拍 << 160拍消隐）预读进FF，
//   显示期纯组合出像素。row-1组专供文字右下1px投影（可读性描边）。
// 时间轴：play_sec由顶层对wav sample_counter（真实消费计数，切图下溢不走词）
//   数48000样本得秒；秒级查表切行（KTV感知足够）。
// 显示：单行居中（18px步进），亮黄FFE000文字 > 黑色投影 > 全透传（与频谱v3.4同风格）。
// 注：INIT_FILE用裸文件名——综合器按源文件所在目录解析（相对syn_1的写法SYN-8142找不到）
module promax_lyric_overlay #(
    parameter integer LYRIC_Y = 376,    // 歌词区顶行（376..391，频谱400上方8px）
    parameter integer H_ACT   = 640
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire        enable,          // wav_active_pix2（仅WAV播放时显示）
    input  wire [1:0]  track_index,
    input  wire [15:0] play_cs,
    output wire [23:0] rgb_out,
    output wire        lyric_active
);
    `include "music_lyric_table.vh"

    localparam integer GLYPH_H     = 16;
    localparam integer CHAR_STRIDE = 18;    // 16px字 + 2px间距
    localparam integer MAXCNT      = 14;    // 最长行字数（脚本保证≤14）

    // ---- 行号重建（与OSD/频谱同款：vsync低清零、de下降沿累加） ----
    reg [11:0] line_y;
    reg de_q;
    reg vs_q;

    // ---- 当前行查找与行属性（组合） ----
    wire [6:0]  line_idx    = enable ? line_of_track_cs(track_index, play_cs) : LYRIC_NONE;
    wire [15:0] meta        = line_meta(line_idx);
    wire [10:0] char_offset = meta[15:5];
    wire [4:0]  char_count  = meta[4:0];
    wire        has_lyric   = (line_idx != LYRIC_NONE);

    // ---- 预读触发：行结束沿，且下一行落在歌词区[LYRIC_Y, LYRIC_Y+16) ----
    wire [11:0] y_next   = line_y + 1'b1;
    wire        pre_kick = de_q && !de && has_lyric &&
                           (y_next >= LYRIC_Y[11:0]) && (y_next < LYRIC_Y[11:0] + GLYPH_H);
    wire [3:0]  kick_row = y_next - LYRIC_Y[11:0];      // 0..15

    // ---- 预读FSM：LD_RUN每拍发一个地址并收上拍数据（BRAM同步读1拍延迟） ----
    // 前半读row行字形（line_ff0），后半读row-1行（line_ff1，投影参考）；row=0只读前半
    localparam LD_IDLE = 1'b0;
    localparam LD_RUN  = 1'b1;
    reg        ld_state;
    reg  [5:0] ld_cnt;      // 0..ld_total
    reg  [5:0] ld_total;
    reg  [4:0] ld_cmax;     // kick时锁存的char_count
    reg [10:0] ld_off;
    reg  [3:0] ld_row;
    // 当拍读取参数（组合）
    wire        ld_half = (ld_cnt >= {1'b0, ld_cmax});          // 后半=row-1投影组
    wire [4:0]  ld_ci   = ld_half ? (ld_cnt[4:0] - ld_cmax) : ld_cnt[4:0];
    wire [3:0]  ld_rrow = ld_half ? (ld_row - 1'b1) : ld_row;
    wire [7:0]  ld_cidx = char_at(ld_off + {6'd0, ld_ci});
    // BRAM读数据对齐打拍（上拍地址对应的本拍数据归属）
    reg [4:0] d_ci;
    reg       d_half;
    reg [1:0] d_blk;
    // 预读完成的行号与有效标记（显示侧比对）
    reg [3:0] buf_row;
    reg       buf_valid;

    // 字形行缓冲：line_ff0=本行文字、line_ff1=上一行（投影用）
    reg [15:0] line_ff0 [0:MAXCNT-1];
    reg [15:0] line_ff1 [0:MAXCNT-1];

    // ---- 4块9K BRAM字形ROM（512×18bit；地址={字idx[4:0],行[3:0]}，块选=字idx[6:5]） ----
    wire [8:0] bram_addr = {ld_cidx[4:0], ld_rrow};
    wire       bram_ce   = (ld_state == LD_RUN) && (ld_cnt < ld_total);
    wire [17:0] doa0, doa1, doa2, doa3;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18), .ADDR_WIDTH_A(9), .MODE("SP"), .REGMODE_A("OUTREG"),
        .INIT_FILE("music_lyric_glyph_b0.mif")
    ) u_glyph_b0 (
        .dia(18'd0), .addra(bram_addr), .cea(bram_ce), .ocea(1'b1), .clka(clk),
        .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(18'd0), .addrb(9'd0), .ceb(1'b0), .oceb(1'b0), .clkb(1'b0),
        .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(doa0), .dob()
    );
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18), .ADDR_WIDTH_A(9), .MODE("SP"), .REGMODE_A("OUTREG"),
        .INIT_FILE("music_lyric_glyph_b1.mif")
    ) u_glyph_b1 (
        .dia(18'd0), .addra(bram_addr), .cea(bram_ce), .ocea(1'b1), .clka(clk),
        .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(18'd0), .addrb(9'd0), .ceb(1'b0), .oceb(1'b0), .clkb(1'b0),
        .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(doa1), .dob()
    );
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18), .ADDR_WIDTH_A(9), .MODE("SP"), .REGMODE_A("OUTREG"),
        .INIT_FILE("music_lyric_glyph_b2.mif")
    ) u_glyph_b2 (
        .dia(18'd0), .addra(bram_addr), .cea(bram_ce), .ocea(1'b1), .clka(clk),
        .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(18'd0), .addrb(9'd0), .ceb(1'b0), .oceb(1'b0), .clkb(1'b0),
        .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(doa2), .dob()
    );
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18), .ADDR_WIDTH_A(9), .MODE("SP"), .REGMODE_A("OUTREG"),
        .INIT_FILE("music_lyric_glyph_b3.mif")
    ) u_glyph_b3 (
        .dia(18'd0), .addra(bram_addr), .cea(bram_ce), .ocea(1'b1), .clka(clk),
        .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(18'd0), .addrb(9'd0), .ceb(1'b0), .oceb(1'b0), .clkb(1'b0),
        .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(doa3), .dob()
    );
    // 数据归属块选按上拍地址选择
    wire [15:0] bram_do = (d_blk == 2'd0) ? doa0[15:0] :
                          (d_blk == 2'd1) ? doa1[15:0] :
                          (d_blk == 2'd2) ? doa2[15:0] :
                                            doa3[15:0];

    // ---- 显示侧位置（组合） ----
    wire [11:0] row12    = line_y - LYRIC_Y[11:0];
    wire        in_lyric = enable && has_lyric && buf_valid && de &&
                           (line_y >= LYRIC_Y[11:0]) && (line_y < LYRIC_Y[11:0] + GLYPH_H) &&
                           (buf_row == row12[3:0]);
    // 文字区横向：start_x=(640-count*18)/2 居中（count*18=count*16+count*2）
    wire [9:0]  text_w   = {5'd0, char_count, 4'b0} + {7'd0, char_count, 1'b0};
    wire [9:0]  start_x  = (10'd640 - text_w) >> 1;
    wire        in_txt   = in_lyric && (pixel_x >= start_x) && (pixel_x < start_x + text_w);

    reg [4:0] char_i;      // 字序号0..13（区外复位，同频谱slot_cnt风格）
    reg [4:0] col_cnt;     // 字内列0..17

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            ld_state <= LD_IDLE;
            ld_cnt <= 6'd0;
            ld_total <= 6'd0;
            ld_cmax <= 5'd0;
            ld_off <= 11'd0;
            ld_row <= 4'd0;
            d_ci <= 5'd0;
            d_half <= 1'b0;
            d_blk <= 2'd0;
            buf_row <= 4'hF;
            buf_valid <= 1'b0;
            char_i <= 5'd0;
            col_cnt <= 5'd0;
            for (k = 0; k < MAXCNT; k = k + 1) begin
                line_ff0[k] <= 16'd0;
                line_ff1[k] <= 16'd0;
            end
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;

            // ---- 预读FSM ----
            case (ld_state)
            LD_IDLE: begin
                if (pre_kick) begin
                    ld_state <= LD_RUN;
                    ld_cnt <= 6'd0;
                    ld_row <= kick_row;
                    ld_cmax <= char_count;
                    ld_off <= char_offset;
                    ld_total <= (kick_row == 4'd0) ? {1'b0, char_count}
                                                   : ({1'b0, char_count} << 1);
                end
            end
            LD_RUN: begin
                // 上拍地址的数据本拍到达，写入对应组（收尾拍同样要收）
                if (ld_cnt != 6'd0) begin
                    if (d_half) line_ff1[d_ci] <= bram_do;
                    else        line_ff0[d_ci] <= bram_do;
                end
                if (ld_cnt == ld_total) begin
                    buf_row <= ld_row;
                    buf_valid <= 1'b1;
                    ld_state <= LD_IDLE;
                    ld_cnt <= 6'd0;
                end else begin
                    d_ci <= ld_ci;
                    d_half <= ld_half;
                    d_blk <= ld_cidx[6:5];
                    ld_cnt <= ld_cnt + 1'b1;
                end
            end
            endcase

            // ---- 显示侧字/列计数 ----
            if (!in_txt) begin
                char_i <= 5'd0;
                col_cnt <= 5'd0;
            end else if (col_cnt == CHAR_STRIDE-1) begin
                col_cnt <= 5'd0;
                char_i <= char_i + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    // ---- 文字/投影判定（组合） ----
    wire [15:0] cur_g  = line_ff0[char_i];
    wire [15:0] prev_g = line_ff1[char_i];
    wire        col_ok = (col_cnt < 5'd16);
    wire [3:0]  bitidx = 4'd15 - col_cnt[3:0];              // bit15=最左像素
    wire        txt_p  = in_txt && col_ok && (char_i < char_count) && cur_g[bitidx];
    // 投影：本像素为黑 ⟺ 左上一像素(x-1,row-1)为文字；row=0无上方参考
    wire        sh_p   = in_txt && col_ok && (char_i < char_count) &&
                         (row12[3:0] != 4'd0) && (col_cnt > 5'd0) && prev_g[bitidx + 1'b1];

    assign lyric_active = txt_p || sh_p;
    // 优先级：亮黄文字 > 黑色投影 > 全透传（v3.4频谱同款无背景风格）
    assign rgb_out = txt_p ? 24'hFFE000 :
                     sh_p  ? 24'h000000 :
                     rgb_in;
endmodule
