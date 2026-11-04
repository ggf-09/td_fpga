`timescale 1ns/1ps

// 第12课扩展：64段胶囊柱彩虹音频频谱（Goertzel滤波器组，真频率分离）
// 用户定制版v3（参照网易云式可视化效果）：
//   ①64段4px细柱近乎全屏宽（面板0..640）  ②柱以面板中线为轴上下对称生长
//   ③每柱独立色相、整屏平滑彩虹扫过（品红→蓝→青→绿→黄→橙→红→玫红，LUT离线生成）
//   ④柱头圆角（端行仅中心2px）  ⑤背景全透传（v3.4起，原为深色半透明面板）  ⑥最小高度2px胶囊
// v3.1资源瘦身（64段首版LUT冲到55.8%导致全局hold修复失败-63ps，瘦身三招）：
//   ①色LUT 24位→12位（4bit/通道，输出复制成8位，彩虹饱和度无感）
//   ②状态32位→24位（输入缩放>>>5，DC增益最坏4.2M<2^23有余量；乘法18x24省DSP拼接）
//   ③柱高去掉归一化细分（每bit 4px步进，肉眼无差）
// v3.2显示侧除法器瘦身：pixel_x/10 改 slot_cnt/bar_idx 计数器（面板行外复位对齐）
// v3.3状态搬BRAM（第14课后LUT 54.3%仍偶发hold违例，再省约700 LUT，勿还原）：
//   s1/s2两条64x24数组（FF实现时读Mux+写解码是大头）打包成一条64x48单口BRAM
//   （{s1,s2}，fehdl force_ram强制BRAM，3072bit<9k）；同步读1拍延迟，状态机
//   由2拍/路改3拍/路（等读/算乘/写回）：样本192拍<520拍间隔、消隐期结算192拍
//   <<1.44ms，时序余量充足。bar_h保持FF数组（显示侧每槽都要随机读）。
//   注：曾试移位链方案，多路驱动使每FF D端长成Mux反多585 LUT，已回退。
// v3.4去黑色背景（参考topic1_student_reference的promax_audio_waveform叠加风格）：
//   ①面板区不再压暗原图，非柱像素全透传（消除"黑色背景"，柱间透出原图）
//   ②参考工程同款1px暗青中线轴（24'h406060）：柱隙/静音时可见频谱基线
//   压暗逻辑删除反省LUT，对hold时序只有好处；spectrum_active扩为柱||中线
// 原理：64路Goertzel谐振器（N=800=每帧样本数，60Hz分辨率，120Hz~16.8kHz），
//   每路只需1次乘法，64路在25MHz下时分复用；每帧(场消隐)结算各路状态幅度
//   →对数柱高(顶部位定位)→快攻慢放(衰减4px/帧)。
module promax_audio_spectrum #(
    parameter integer WAVE_X = 0,
    parameter integer WAVE_Y = 400,
    parameter integer WAVE_WIDTH = 640,
    parameter integer WAVE_HEIGHT = 64
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire        enable,
    input  wire        pcm_tap_valid,
    input  wire signed [15:0] pcm_tap_left,
    output wire [23:0] rgb_out,
    output wire        spectrum_active
);
    localparam integer BANDS    = 64;
    localparam integer BAR_SLOT = WAVE_WIDTH / BANDS;   // 10px槽
    localparam integer BAR_W    = 4;                    // 柱宽4px（偏置3，两侧各留3px）
    localparam integer CENTER_Y = WAVE_Y + WAVE_HEIGHT/2; // 中线y=432
    localparam integer H_FLOOR  = 8;                    // 对数柱高起始位（抑噪；输入>>>5配套）

    // ---- Goertzel系数 2cos(2*pi*k/800)，Q3.15（18位signed）----
    // 64频点：低端60Hz线性步进、高端对数，120Hz ~ 16800Hz
    function signed [17:0] coeff_of;
        input [5:0] idx;
        begin
            case (idx)
                6'd0 : coeff_of = 18'sd65528;
                6'd1 : coeff_of = 18'sd65518;
                6'd2 : coeff_of = 18'sd65504;
                6'd3 : coeff_of = 18'sd65485;
                6'd4 : coeff_of = 18'sd65463;
                6'd5 : coeff_of = 18'sd65437;
                6'd6 : coeff_of = 18'sd65407;
                6'd7 : coeff_of = 18'sd65372;
                6'd8 : coeff_of = 18'sd65334;
                6'd9 : coeff_of = 18'sd65292;
                6'd10: coeff_of = 18'sd65245;
                6'd11: coeff_of = 18'sd65195;
                6'd12: coeff_of = 18'sd65140;
                6'd13: coeff_of = 18'sd65082;
                6'd14: coeff_of = 18'sd65019;
                6'd15: coeff_of = 18'sd64953;
                6'd16: coeff_of = 18'sd64882;
                6'd17: coeff_of = 18'sd64808;
                6'd18: coeff_of = 18'sd64729;
                6'd19: coeff_of = 18'sd64647;
                6'd20: coeff_of = 18'sd64560;
                6'd21: coeff_of = 18'sd64470;
                6'd22: coeff_of = 18'sd64375;
                6'd23: coeff_of = 18'sd64277;
                6'd24: coeff_of = 18'sd64174;
                6'd25: coeff_of = 18'sd64068;
                6'd26: coeff_of = 18'sd63958;
                6'd27: coeff_of = 18'sd63843;
                6'd28: coeff_of = 18'sd63725;
                6'd29: coeff_of = 18'sd63603;
                6'd30: coeff_of = 18'sd63477;
                6'd31: coeff_of = 18'sd63347;
                6'd32: coeff_of = 18'sd63213;
                6'd33: coeff_of = 18'sd63075;
                6'd34: coeff_of = 18'sd62934;
                6'd35: coeff_of = 18'sd62788;
                6'd36: coeff_of = 18'sd62639;
                6'd37: coeff_of = 18'sd62486;
                6'd38: coeff_of = 18'sd62328;
                6'd39: coeff_of = 18'sd61834;
                6'd40: coeff_of = 18'sd61305;
                6'd41: coeff_of = 18'sd60547;
                6'd42: coeff_of = 18'sd59730;
                6'd43: coeff_of = 18'sd58853;
                6'd44: coeff_of = 18'sd57676;
                6'd45: coeff_of = 18'sd56410;
                6'd46: coeff_of = 18'sd54775;
                6'd47: coeff_of = 18'sd53020;
                6'd48: coeff_of = 18'sd51146;
                6'd49: coeff_of = 18'sd48817;
                6'd50: coeff_of = 18'sd45976;
                6'd51: coeff_of = 18'sd42952;
                6'd52: coeff_of = 18'sd39349;
                6'd53: coeff_of = 18'sd35116;
                6'd54: coeff_of = 18'sd30666;
                6'd55: coeff_of = 18'sd25554;
                6'd56: coeff_of = 18'sd19270;
                6'd57: coeff_of = 18'sd12785;
                6'd58: coeff_of = 18'sd5655;
                6'd59: coeff_of = -18'sd2573;
                6'd60: coeff_of = -18'sd10760;
                6'd61: coeff_of = -18'sd19762;
                6'd62: coeff_of = -18'sd29293;
                6'd63: coeff_of = -18'sd38521;
                default: coeff_of = 18'sd0;
            endcase
        end
    endfunction

    // ---- 柱色LUT：每柱独立色相，品红起逆时针满圈扫过（12位色深，Python离线生成）----
    function [11:0] color_of;
        input [5:0] idx;
        begin
            case (idx)
                6'd0 : color_of = 12'hF1F;
                6'd1 : color_of = 12'hE1F;
                6'd2 : color_of = 12'hC1F;
                6'd3 : color_of = 12'hB1F;
                6'd4 : color_of = 12'hA1F;
                6'd5 : color_of = 12'h91F;
                6'd6 : color_of = 12'h71F;
                6'd7 : color_of = 12'h61F;
                6'd8 : color_of = 12'h51F;
                6'd9 : color_of = 12'h41F;
                6'd10: color_of = 12'h21F;
                6'd11: color_of = 12'h12F;
                6'd12: color_of = 12'h13F;
                6'd13: color_of = 12'h14F;
                6'd14: color_of = 12'h16F;
                6'd15: color_of = 12'h17F;
                6'd16: color_of = 12'h18F;
                6'd17: color_of = 12'h1AF;
                6'd18: color_of = 12'h1BF;
                6'd19: color_of = 12'h1CF;
                6'd20: color_of = 12'h1DF;
                6'd21: color_of = 12'h1FF;
                6'd22: color_of = 12'h1FE;
                6'd23: color_of = 12'h1FD;
                6'd24: color_of = 12'h1FC;
                6'd25: color_of = 12'h1FA;
                6'd26: color_of = 12'h1F9;
                6'd27: color_of = 12'h1F8;
                6'd28: color_of = 12'h1F7;
                6'd29: color_of = 12'h1F5;
                6'd30: color_of = 12'h1F4;
                6'd31: color_of = 12'h1F3;
                6'd32: color_of = 12'h1F1;
                6'd33: color_of = 12'h3F1;
                6'd34: color_of = 12'h4F1;
                6'd35: color_of = 12'h5F1;
                6'd36: color_of = 12'h7F1;
                6'd37: color_of = 12'h8F1;
                6'd38: color_of = 12'h9F1;
                6'd39: color_of = 12'hAF1;
                6'd40: color_of = 12'hCF1;
                6'd41: color_of = 12'hDF1;
                6'd42: color_of = 12'hEF1;
                6'd43: color_of = 12'hFF1;
                6'd44: color_of = 12'hFD1;
                6'd45: color_of = 12'hFC1;
                6'd46: color_of = 12'hFB1;
                6'd47: color_of = 12'hFA1;
                6'd48: color_of = 12'hF81;
                6'd49: color_of = 12'hF71;
                6'd50: color_of = 12'hF61;
                6'd51: color_of = 12'hF41;
                6'd52: color_of = 12'hF31;
                6'd53: color_of = 12'hF21;
                6'd54: color_of = 12'hF12;
                6'd55: color_of = 12'hF14;
                6'd56: color_of = 12'hF15;
                6'd57: color_of = 12'hF16;
                6'd58: color_of = 12'hF17;
                6'd59: color_of = 12'hF19;
                6'd60: color_of = 12'hF1A;
                6'd61: color_of = 12'hF1B;
                6'd62: color_of = 12'hF1C;
                6'd63: color_of = 12'hF1E;
                default: color_of = 12'hFFF;
            endcase
        end
    endfunction

    reg [6:0] bar_h [0:BANDS-1];   // 显示柱高0..63（快攻慢放后，FF数组：每槽随机读）

    // ---- 行号重建与frame_start（与OSD/波形模块同款）----
    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    wire frame_start = vs_q && !vsync;

    // ---- 处理状态机（v3.3：BRAM同步读，3拍/路）----
    // 样本通路：ST_RD(等读) → ST_MUL(锁存s1/s2、算乘) → ST_ACC(写回{s1新,s1旧})
    // 结算通路：ST_URD(等读) → ST_UCAL(能量→柱高→bar_h) → ST_UWR(写回0清零)
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_RD   = 3'd1;
    localparam [2:0] ST_MUL  = 3'd2;
    localparam [2:0] ST_ACC  = 3'd3;
    localparam [2:0] ST_URD  = 3'd4;
    localparam [2:0] ST_UCAL = 3'd5;
    localparam [2:0] ST_UWR  = 3'd6;
    reg [2:0] state;
    reg [5:0] idx;
    reg       upd_pending;
    reg signed [31:0] x_lat;             // 样本锁存（>>>5缩放防溢出）
    reg signed [41:0] mult;              // coeff(18b) × s1(24b)
    reg signed [23:0] s1_lat;            // ST_MUL锁存的读数（ST_ACC写回用）
    reg signed [23:0] s2_lat;

    wire signed [26:0] acc_sh = mult[41:15];                 // Q3.15去归一化
    wire signed [31:0] new_s_full = x_lat + acc_sh - s2_lat; // Goertzel递推

    // ---- v3.3：s1/s2打包一条64x48单口BRAM（{s1,s2}，同步读1拍延迟）----
    reg [47:0] state_ram [0:BANDS-1] /* fehdl force_ram=1, ram_style="bram" */;
    reg [5:0]  ram_addr;
    reg [47:0] ram_rdata;
    // 写使能/写数据组合产生：写发生在ST_ACC/ST_UWR当拍（当拍ram_addr仍=idx），
    // 若改成寄存器会晚一拍、地址已翻到下一路——勿改回寄存器写法
    wire        ram_we    = (state == ST_ACC) || (state == ST_UWR);
    wire [47:0] ram_wdata = (state == ST_ACC) ? {new_s_full[23:0], s1_lat} : 48'd0;
    always @(posedge clk) begin
        if (ram_we)
            state_ram[ram_addr] <= ram_wdata;
        ram_rdata <= state_ram[ram_addr];   // 同步读；同拍写时读旧值（调度上不会用到）
    end
    // 帧结算读数（ST_UCAL期间ram_rdata有效）
    wire signed [23:0] s1_i = ram_rdata[47:24];
    wire signed [23:0] s2_i = ram_rdata[23:0];
    wire [23:0] abs1 = s1_i[23] ? (~s1_i + 1'b1) : s1_i;
    wire [23:0] abs2 = s2_i[23] ? (~s2_i + 1'b1) : s2_i;
    wire [24:0] mag  = {1'b0, abs1} + {1'b0, abs2};          // 帧能量估计 |s1|+|s2|

    // 顶部位定位（25位→5位）
    function [4:0] topbit;
        input [24:0] v;
        integer j;
        begin
            topbit = 5'd0;
            for (j = 0; j < 25; j = j + 1)
                if (v[j]) topbit = j[4:0];
        end
    endfunction

    wire [4:0] mb = topbit(mag);
    wire [8:0] hraw = (mb > H_FLOOR) ? (({4'd0, mb} - H_FLOOR) << 2) : 9'd0;
    wire [6:0] hnew = (hraw > 9'd63) ? 7'd63 : hraw[6:0];

    // ---- 显示侧位置计数（v3.2：替代 pixel_x/10 除法器；面板行外复位与x=0对齐）----
    wire in_panel = enable && de &&
                    line_y >= WAVE_Y && line_y < WAVE_Y + WAVE_HEIGHT;
    reg [5:0] bar_idx;     // 当前槽0..63（bar_h/color_of索引用）
    reg [3:0] slot_cnt;    // 槽内像素0..9

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            state <= ST_IDLE;
            idx <= 6'd0;
            upd_pending <= 1'b0;
            x_lat <= 32'sd0;
            mult <= 42'sd0;
            s1_lat <= 24'sd0;
            s2_lat <= 24'sd0;
            bar_idx <= 6'd0;
            slot_cnt <= 4'd0;
            ram_addr <= 6'd0;
            for (i = 0; i < BANDS; i = i + 1)
                bar_h[i] <= 7'd0;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;

            if (frame_start)
                upd_pending <= 1'b1;

            // 显示侧槽/柱计数（面板行外复位，保证每条面板行从槽0起步）
            if (!in_panel) begin
                bar_idx  <= 6'd0;
                slot_cnt <= 4'd0;
            end else if (slot_cnt == BAR_SLOT-1) begin
                slot_cnt <= 4'd0;
                bar_idx  <= bar_idx + 1'b1;   // 63+1回卷成0（6位截断）
            end else begin
                slot_cnt <= slot_cnt + 1'b1;
            end

            case (state)
            ST_IDLE: begin
                if (upd_pending) begin
                    upd_pending <= 1'b0;
                    idx <= 6'd0;
                    ram_addr <= 6'd0;         // 发起band0读
                    state <= ST_URD;
                end else if (pcm_tap_valid && enable) begin
                    x_lat <= {{16{pcm_tap_left[15]}}, pcm_tap_left} >>> 5;
                    idx <= 6'd0;
                    ram_addr <= 6'd0;         // 发起band0读
                    state <= ST_RD;
                end
            end
            // ---- 样本通路：读 → 算乘 → 写回 ----
            ST_RD: begin                       // 等同步读数据（本拍末ram_rdata有效）
                state <= ST_MUL;
            end
            ST_MUL: begin
                s1_lat <= ram_rdata[47:24];
                s2_lat <= ram_rdata[23:0];
                mult   <= coeff_of(idx) * $signed(ram_rdata[47:24]);  // 18b×24b=42b
                state  <= ST_ACC;
            end
            ST_ACC: begin
                // 写使能/数据由组合逻辑在当拍产生（ram_we=state==ST_ACC），写回同址idx
                ram_addr  <= idx + 1'b1;      // 同时预发下一路读地址
                idx <= idx + 1'b1;
                state <= (idx == BANDS-1) ? ST_IDLE : ST_RD;
            end
            // ---- 帧结算通路：读 → 结算柱高 → 写0 ----
            ST_URD: begin
                state <= ST_UCAL;
            end
            ST_UCAL: begin  // 能量→对数柱高→快攻慢放(衰减4px/帧)
                if (hnew > bar_h[idx])
                    bar_h[idx] <= hnew;
                else
                    bar_h[idx] <= (bar_h[idx] > 7'd4) ? bar_h[idx] - 7'd4 : 7'd0;
                state <= ST_UWR;
            end
            ST_UWR: begin
                // 当拍组合写回48'd0清零本路状态
                ram_addr  <= idx + 1'b1;      // 预发下一路读地址
                idx <= idx + 1'b1;
                state <= (idx == BANDS-1) ? ST_IDLE : ST_URD;
            end
            default: state <= ST_IDLE;
            endcase
        end
    end

    // ---- 显示侧（组合逻辑）：中线对称胶囊柱+圆角端头 ----
    integer h_eff;
    integer y_top;
    integer y_bot;
    reg bar_pixel;
    reg end_row;
    reg [6:0] cur_h;

    always @* begin
        h_eff = 2;
        y_top = CENTER_Y;
        y_bot = CENTER_Y;
        cur_h = 7'd0;
        bar_pixel = 1'b0;
        end_row = 1'b0;

        if (in_panel) begin
            cur_h = bar_h[bar_idx];
            h_eff = cur_h >> 1;                  // 半高0..31（上下对称）
            if (h_eff < 2) h_eff = 2;            // 最小2px胶囊
            y_top = CENTER_Y - h_eff;
            y_bot = CENTER_Y + h_eff;
            if (line_y >= y_top && line_y <= y_bot) begin
                end_row = (line_y == y_top || line_y == y_bot);
                // 圆角：端行仅中心2px；柱体行4px
                if (end_row)
                    bar_pixel = (slot_cnt >= 4 && slot_cnt < 6);
                else
                    bar_pixel = (slot_cnt >= 3 && slot_cnt < 3+BAR_W);
            end
        end
    end

    wire [11:0] bar_c12 = color_of(bar_idx);
    // 12位色深复制成24位（4bit/通道→8bit，彩虹饱和度无感）
    wire [23:0] bar_color = {bar_c12[11:8], bar_c12[11:8],
                             bar_c12[7:4],  bar_c12[7:4],
                             bar_c12[3:0],  bar_c12[3:0]};

    // v3.4：参考工程同款1px暗青中线轴（面板行内、与柱中线同高）
    wire axis_pixel = in_panel && (line_y == CENTER_Y);

    assign spectrum_active = bar_pixel || axis_pixel;
    // v3.4：黑色背景已消除——非柱/非轴像素全透传原图（原深色半透明面板删除）
    // 优先级：柱本体(全亮LUT彩虹色) > 暗青中线轴 > 原图透传
    assign rgb_out = bar_pixel ? bar_color :
                     axis_pixel ? 24'h406060 :
                     rgb_in;
endmodule
