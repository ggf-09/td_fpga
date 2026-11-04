`timescale 1ns/1ps
// Simulation-only FIFO contract model; no vendor encryption or device model.
module rfifo_32_32_512 #(
    parameter DATA_WIDTH_W=32, DATA_WIDTH_R=32,
    parameter ADDR_WIDTH_W=9, ADDR_WIDTH_R=9,
    parameter AL_FULL_NUM=504, AL_EMPTY_NUM=2,
    parameter SHOW_AHEAD_EN=0, OUTREG_EN="NOREG"
) (
    input rst,clkw,clkr,we,re,
    input [DATA_WIDTH_W-1:0] di,
    output reg [DATA_WIDTH_R-1:0] dout,
    output reg valid,
    output full_flag,empty_flag,afull,aempty,
    output [ADDR_WIDTH_W-1:0] wrusedw,
    output [ADDR_WIDTH_R-1:0] rdusedw
);
    localparam DEPTH=1<<ADDR_WIDTH_W;
    reg [31:0] mem[0:DEPTH-1];
    integer wp=0,rp=0;
    wire [31:0] used=wp-rp;
    assign full_flag=used==DEPTH;
    assign empty_flag=used==0;
    assign afull=used>=AL_FULL_NUM;
    assign aempty=used<=AL_EMPTY_NUM;
    reg [ADDR_WIDTH_W-1:0] used_delayed=0;
    always @(posedge clkw or posedge rst)if(rst)used_delayed<=0;else used_delayed<=used;
    assign wrusedw=used_delayed;
    assign rdusedw=used;
    always @(posedge clkw or posedge rst) begin
        if(rst) wp<=0;
        else if(we && !full_flag) begin mem[wp%DEPTH]<=di; wp<=wp+1; end
    end
    always @(posedge clkr or posedge rst) begin
        if(rst) begin rp<=0; valid<=0; dout<=0; end
        else begin
            valid<=0;
            if(re && !empty_flag) begin dout<=mem[rp%DEPTH]; rp<=rp+1; valid<=1; end
        end
    end
endmodule
