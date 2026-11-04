`timescale 1ns/1ps
// ram32k_dp8.v —— 4096x8 双时钟双口 RAM，FPGA 上映射到 1 块 EG_PHY_BRAM32K
// （低字节模式：2048x16 原生宽度只用低 8 位，用 2 块拼 4096 深度）。
// 仿真（iverilog 定义 __ICARUS__）走行为模型，综合走 EG4 原语。
// 读为同步读：地址/写使能在时钟沿采样，数据下一拍有效（与推断 BRAM 一致）。
// 写模式 NORMAL：同地址同拍读写时读出旧数据。
module ram32k_dp8 (
    input  wire        clka,
    input  wire        wea,
    input  wire [11:0] addra,
    input  wire [7:0]  dia,
    output wire [7:0]  doa,
    input  wire        clkb,
    input  wire [11:0] addrb,
    output wire [7:0]  dob
);
`ifdef BRAM32K_BEHAVIORAL
    // ---------- 行为模型（显式 -D/垫片宏 开关） ----------
    reg [7:0] mem [0:4095];
    reg [7:0] doa_r, dob_r;
    always @(posedge clka) begin
        if (wea) mem[addra] <= dia;
        doa_r <= mem[addra];
    end
    always @(posedge clkb) begin
        dob_r <= mem[addrb];
    end
    assign doa = doa_r;
    assign dob = dob_r;
`elsif __ICARUS__
    // ---------- 行为模型（iverilog 自动宏兜底） ----------
    reg [7:0] mem [0:4095];
    reg [7:0] doa_r, dob_r;
    always @(posedge clka) begin
        if (wea) mem[addra] <= dia;
        doa_r <= mem[addra];
    end
    always @(posedge clkb) begin
        dob_r <= mem[addrb];
    end
    assign doa = doa_r;
    assign dob = dob_r;
`else
    // ---------- EG4 原语：2 块 2048x16（只用低字节） ----------
    wire [15:0] doa_lo, doa_hi, dob_lo, dob_hi;
    reg         addra_hi_q, addrb_hi_q;
    always @(posedge clka) addra_hi_q <= addra[11];
    always @(posedge clkb) addrb_hi_q <= addrb[11];
    assign doa = addra_hi_q ? doa_hi[7:0] : doa_lo[7:0];
    assign dob = addrb_hi_q ? dob_hi[7:0] : dob_lo[7:0];

    EG_PHY_BRAM32K #(
        .MODE("DP16K"), .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL")
    ) u_lo (
        .clka(clka), .rsta(1'b0), .ocea(1'b1),
        .csa(!addra[11]), .wea(wea && !addra[11]),
        .addra(addra[10:0]), .dia({8'd0, dia}), .doa(doa_lo),
        .bytea(1'b0), .bytewea(1'b0),
        .clkb(clkb), .rstb(1'b0), .oceb(1'b1),
        .csb(!addrb[11]), .web(1'b0),
        .addrb(addrb[10:0]), .dib(16'd0), .dob(dob_lo),
        .byteb(1'b0), .byteweb(1'b0)
    );
    EG_PHY_BRAM32K #(
        .MODE("DP16K"), .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL")
    ) u_hi (
        .clka(clka), .rsta(1'b0), .ocea(1'b1),
        .csa(addra[11]), .wea(wea && addra[11]),
        .addra(addra[10:0]), .dia({8'd0, dia}), .doa(doa_hi),
        .bytea(1'b0), .bytewea(1'b0),
        .clkb(clkb), .rstb(1'b0), .oceb(1'b1),
        .csb(addrb[11]), .web(1'b0),
        .addrb(addrb[10:0]), .dib(16'd0), .dob(dob_hi),
        .byteb(1'b0), .byteweb(1'b0)
    );
`endif
endmodule
