`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// 第8课：video_timing_ctrl（视频时序控制器，替换官方 video_timing_data）
// 来源：第8课参考代码，原样使用。
// 像素时钟域内的行/场计数器 + 同拍组合译码：
//   x/y  : 行/场计数器本体，0..H_TOTAL-1 / 0..V_TOTAL-1；de=1时即有效像素坐标
//   de   : 有效显示区，(x < H_ACT) && (y < V_ACT)
//   hsync: 低有效行同步，位于 [H_ACT+H_FP, H_ACT+H_FP+H_SYNC)
//   vsync: 低有效场同步，位于 [V_ACT+V_FP, V_ACT+V_FP+V_SYNC)
// 段顺序 ACTIVE -> FRONT PORCH -> SYNC -> BACK PORCH（与官方color_bar一致，
// 因此 ACTIVE_LAST=0；HDMI核按时序参数自行重建输出时序）。
// -----------------------------------------------------------------------------
module video_timing_ctrl #(
    parameter H_ACT  = 640,  // 水平有效像素
    parameter H_FP   = 16,   // 水平前肩
    parameter H_SYNC = 96,   // 水平同步脉宽
    parameter H_BP   = 48,   // 水平后肩
    parameter V_ACT  = 480,  // 垂直有效行
    parameter V_FP   = 10,   // 垂直前肩
    parameter V_SYNC = 2,    // 垂直同步脉宽
    parameter V_BP   = 33,   // 垂直后肩
    parameter ACTIVE_LAST = 0
)(
    input  wire        pclk,   // 像素时钟（25MHz，video_pll产生）
    input  wire        rst_n,  // 低有效复位
    output wire        hsync,  // 低有效
    output wire        vsync,  // 低有效
    output wire        de,     // 有效显示区
    output reg  [11:0] x,      // 行计数器；de=1时为有效像素列坐标
    output reg  [11:0] y       // 场计数器；de=1时为有效像素行坐标
);

    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;

    // 行/场计数：x走完一行，y走一步；两个都走完回到帧起点(0,0)
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 12'd0;
            y <= 12'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 12'd0;
            y <= (y == V_TOTAL - 1) ? 12'd0 : y + 12'd1;
        end else begin
            x <= x + 12'd1;
        end
    end

    // 同拍组合译码：de/hsync/vsync与x/y永远对齐，不存在错拍问题
    assign de    = ACTIVE_LAST ?
                   ((x >= H_TOTAL - H_ACT) && (y >= V_TOTAL - V_ACT)) :
                   ((x < H_ACT) && (y < V_ACT));
    assign hsync = ACTIVE_LAST ?
                   ~((x >= H_FP) && (x < H_FP + H_SYNC)) :
                   ~((x >= H_ACT + H_FP) && (x < H_ACT + H_FP + H_SYNC));
    assign vsync = ACTIVE_LAST ?
                   ~((y >= V_FP) && (y < V_FP + V_SYNC)) :
                   ~((y >= V_ACT + V_FP) && (y < V_ACT + V_FP + V_SYNC));

endmodule
