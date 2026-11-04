`timescale 1ns/1ps

// SD卡扇区读接口适配层（第7课新增）
// 把完赛工程FAT32模块的sector_*接口，转换成官方sd_card_top的sd_sec_*接口。
// 解决三个接口不匹配问题：
//   1. sector_busy    ：官方sd_card_top没有busy信号，适配层自己生成（请求发出到读完成之间为1）
//   2. sector_byte_index：官方不输出字节索引，适配层自己计数（valid时+1，done时清零）
//   3. sector_error   ：原官方无错误码固定0；现sd_card_sec_read_write新增
//      sd_sec_read_error（CMD17错误响应/等0xFE超时，重试3次仍失败），透传为8'h10，
//      让上层FAT流模块报错退出而不是永久等sector_done（上板部分歌曲卡死的根因）
// 说明：官方sd_card_top的sd_sec_read为电平触发（S_WAIT_READ_WRITE检测到高电平即锁存地址发起读），
//       与本适配层"请求锁存后保持电平、读到end撤销"的行为一致（原bmp_read即按此方式驱动）。
module sd_sector_adapter (
    input  wire        clk,
    input  wire        rst_n,                // 低有效复位
    // === 新模块侧（sector接口，FAT32模块用）===
    input  wire        sector_req,           // 读扇区请求（单拍脉冲）
    input  wire [31:0] sector_lba,           // 扇区号
    output wire        sector_busy,          // 忙（正在读）
    output wire        sector_valid,         // 字节有效脉冲
    output wire [7:0]  sector_byte,          // 当前字节
    output wire [8:0]  sector_byte_index,    // 字节索引（0~511）
    output wire        sector_done,          // 读完成脉冲
    output wire [7:0]  sector_error,         // 错误码（0=成功；8'h10=读失败，重试耗尽）
    // === 官方sd_card_top侧（sd_sec接口）===
    output reg         sd_sec_read,          // 读扇区请求（电平）
    output reg  [31:0] sd_sec_read_addr,     // 扇区号
    input  wire        sd_sec_read_data_valid, // 字节有效
    input  wire [7:0]  sd_sec_read_data,     // 当前字节
    input  wire        sd_sec_read_end,      // 读完成
    input  wire        sd_sec_read_error     // 读失败（与read_end同拍）
);

    reg [8:0] byte_cnt;   // 字节索引计数器（0~511）
    reg       busy_reg;   // 忙寄存器

    // 忙信号：请求发出后到读完成之间为1
    assign sector_busy       = busy_reg;
    // 字节有效和字节直接透传
    assign sector_valid      = sd_sec_read_data_valid;
    assign sector_byte       = sd_sec_read_data;
    assign sector_byte_index = byte_cnt;
    assign sector_done       = sd_sec_read_end;
    // 错误码与done同拍有效：上层流模块在sector_done拍采样sector_error
    assign sector_error      = (sd_sec_read_end && sd_sec_read_error) ? 8'h10 : 8'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_sec_read      <= 1'b0;
            sd_sec_read_addr <= 32'd0;
            byte_cnt         <= 9'd0;
            busy_reg         <= 1'b0;
        end else begin
            // 请求到来且不忙时，锁存扇区号，发出读请求
            if (sector_req && !busy_reg) begin
                sd_sec_read      <= 1'b1;
                sd_sec_read_addr <= sector_lba;
                busy_reg         <= 1'b1;
                byte_cnt         <= 9'd0;
            end
            // 读完成：撤销请求，清零计数器和忙
            else if (sd_sec_read_end) begin
                sd_sec_read <= 1'b0;
                busy_reg    <= 1'b0;
                byte_cnt    <= 9'd0;
            end
            // 读进行中：字节有效时计数器递增
            else if (sd_sec_read_data_valid) begin
                byte_cnt <= byte_cnt + 9'd1;
            end
        end
    end

endmodule
