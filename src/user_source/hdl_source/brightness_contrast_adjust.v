`timescale 1ns/1ps

// 第14课(课件第13课)：亮度/对比度调节（练习骨架+参考答案补全，完赛工程未单独实现）
// 公式：bright = x * coeff / 256；final = saturate((bright-128) * contrast / 128 + 128)
// 本工程两处适配（勿还原）：
//   ①亮度系数改 coeff = (brightness==255) ? 256 : brightness ——brightness=255时
//     x*256>>8=x 逐位无损（回归基准）；比课件完赛的(brightness+1)更精确且低档无偏亮
//   ②去掉课件骨架的输出打拍寄存器，改纯组合——本工程像素链全组合对齐
//     （adapter统一寄存de/rgb，打拍会错1像素，同第10课alpha乘法适配理由）；
//     两级8x8/8x9乘法@25MHz(40ns)时序无压力，DSP 11/29余量充足
module brightness_contrast_adjust (
    input  wire [23:0] rgb_in,
    input  wire [7:0]  brightness,   // 帧边界锁存后的亮度（255=正常）
    input  wire [7:0]  contrast,     // 帧边界锁存后的对比度（128=正常）
    output wire [23:0] rgb_out
);
    // ---- 亮度通路：每通道 × coeff 后取高8位（/256），coeff 9位 ----
    wire [8:0]  bcoeff = (brightness == 8'd255) ? 9'd256 : {1'b0, brightness};
    wire [16:0] mul_r = rgb_in[23:16] * bcoeff;
    wire [16:0] mul_g = rgb_in[15:8] * bcoeff;
    wire [16:0] mul_b = rgb_in[7:0] * bcoeff;
    wire [7:0] bright_r = mul_r[16:8];
    wire [7:0] bright_g = mul_g[16:8];
    wire [7:0] bright_b = mul_b[16:8];

    // ---- 对比度+饱和截断（课件3.2.2参考答案）：(x-128)*contrast>>>7+128 ----
    // 算术右移>>>7实现/128（有符号负数必须算术右移）；contrast=128时输出=输入
    wire signed [8:0]  ctr_r = $signed({1'b0, bright_r}) - 9'sd128;
    wire signed [8:0]  ctr_g = $signed({1'b0, bright_g}) - 9'sd128;
    wire signed [8:0]  ctr_b = $signed({1'b0, bright_b}) - 9'sd128;
    wire signed [16:0] sc_r  = (ctr_r * $signed({1'b0, contrast})) >>> 7;
    wire signed [16:0] sc_g  = (ctr_g * $signed({1'b0, contrast})) >>> 7;
    wire signed [16:0] sc_b  = (ctr_b * $signed({1'b0, contrast})) >>> 7;
    wire signed [9:0]  sum_r = sc_r + 10'sd128;
    wire signed [9:0]  sum_g = sc_g + 10'sd128;
    wire signed [9:0]  sum_b = sc_b + 10'sd128;
    wire [7:0] final_r = (sum_r < 10'sd0)   ? 8'd0   :
                         (sum_r > 10'sd255) ? 8'd255 : sum_r[7:0];
    wire [7:0] final_g = (sum_g < 10'sd0)   ? 8'd0   :
                         (sum_g > 10'sd255) ? 8'd255 : sum_g[7:0];
    wire [7:0] final_b = (sum_b < 10'sd0)   ? 8'd0   :
                         (sum_b > 10'sd255) ? 8'd255 : sum_b[7:0];

    assign rgb_out = {final_r, final_g, final_b};
endmodule
