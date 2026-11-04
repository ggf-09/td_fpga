`timescale 1ns/1ps
// ram32k_dp16.v —— 4096x16 双时钟双口 RAM，FPGA 上映射到 2 块 EG_PHY_BRAM32K
// （原生 2048x16，两块按地址最高位拼接）。仿真走行为模型，综合走 EG4 原语。
// 端口 A（clka）：写；端口 B（clkb）：读。读为同步读：数据下一拍有效。
// 写模式 NORMAL：同地址同拍读写时读出旧数据。
module ram32k_dp16 (
    input  wire        clka,
    input  wire        wea,
    input  wire [11:0] addra,
    input  wire [15:0] dia,
    input  wire        clkb,
    input  wire [11:0] addrb,
    output wire [15:0] dob
);
`ifdef BRAM32K_BEHAVIORAL
    // ---------- 行为模型（显式 -D/垫片宏 开关） ----------
    reg [15:0] mem [0:4095];
    reg [15:0] dob_r;
    always @(posedge clka) begin
        if (wea) mem[addra] <= dia;
    end
    always @(posedge clkb) begin
        dob_r <= mem[addrb];
    end
    assign dob = dob_r;
`elsif __ICARUS__
    // ---------- 行为模型（iverilog 自动宏兜底） ----------
    reg [15:0] mem [0:4095];
    reg [15:0] dob_r;
    always @(posedge clka) begin
        if (wea) mem[addra] <= dia;
    end
    always @(posedge clkb) begin
        dob_r <= mem[addrb];
    end
    assign dob = dob_r;
`else
    // ---------- EG4 原语：2 块 2048x16 ----------
    wire [15:0] dob_lo, dob_hi;
    reg         addrb_hi_q;
    always @(posedge clkb) addrb_hi_q <= addrb[11];
    assign dob = addrb_hi_q ? dob_hi : dob_lo;

    EG_PHY_BRAM32K #(
        .MODE("DP16K"), .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL")
    ) u_lo (
        .clka(clka), .rsta(1'b0), .ocea(1'b1),
        .csa(wea && !addra[11]), .wea(wea && !addra[11]),
        .addra(addra[10:0]), .dia(dia), .doa(),
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
        .csa(wea && addra[11]), .wea(wea && addra[11]),
        .addra(addra[10:0]), .dia(dia), .doa(),
        .bytea(1'b0), .bytewea(1'b0),
        .clkb(clkb), .rstb(1'b0), .oceb(1'b1),
        .csb(addrb[11]), .web(1'b0),
        .addrb(addrb[10:0]), .dib(16'd0), .dob(dob_hi),
        .byteb(1'b0), .byteweb(1'b0)
    );
`endif
endmodule
