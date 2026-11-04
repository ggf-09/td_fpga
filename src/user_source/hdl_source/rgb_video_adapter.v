`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// 第8课：rgb_video_adapter（RGB视频流适配器，替换官方 video_delay）
// 来源：第8课参考代码，原样使用。
// 三个职责：
//   1) 统一寄存一拍：hs/vs/de/rgb整组同拍寄存，给下游HDMI核干净的寄存器输出；
//   2) 极性适配：本工程合同sync低有效；HS/VS_OUT_ACTIVE_LOW按IP要求配置；
//   3) 消隐防护：de=0时video_rgb强制为0，上游脏数据出不了门。
// video_clk = pclk 直通（时钟不走寄存器，走时钟资源）。
// -----------------------------------------------------------------------------
module rgb_video_adapter #(
    parameter HS_IN_ACTIVE_LOW  = 1,  // 本工程合同：低有效
    parameter VS_IN_ACTIVE_LOW  = 1,
    parameter HS_OUT_ACTIVE_LOW = 1,  // 按下游IP要求配置；1=维持低有效
    parameter VS_OUT_ACTIVE_LOW = 1
)(
    input  wire        pclk,       // 像素时钟
    input  wire        rst_n,      // 低有效复位
    input  wire        hs_in,      // 视频流输入
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output wire        video_clk,  // = pclk，直通不寄存
    output reg         video_hs,   // 极性由输出参数决定
    output reg         video_vs,
    output reg         video_de,
    output reg  [23:0] video_rgb   // 消隐期恒0
);

    // 先归一化成"高有效"内部语义，再按输出参数生成——两端极性互相独立
    wire hs_act = HS_IN_ACTIVE_LOW ? ~hs_in : hs_in;
    wire vs_act = VS_IN_ACTIVE_LOW ? ~vs_in : vs_in;

    assign video_clk = pclk;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位=空闲电平：不在同步脉冲里、无有效像素、全黑
            video_hs  <= HS_OUT_ACTIVE_LOW ? 1'b1 : 1'b0;
            video_vs  <= VS_OUT_ACTIVE_LOW ? 1'b1 : 1'b0;
            video_de  <= 1'b0;
            video_rgb <= 24'h000000;
        end else begin
            video_hs  <= HS_OUT_ACTIVE_LOW ? ~hs_act : hs_act;
            video_vs  <= VS_OUT_ACTIVE_LOW ? ~vs_act : vs_act;
            video_de  <= de_in;
            video_rgb <= de_in ? rgb_in : 24'h000000;  // 消隐防护
        end
    end

endmodule
