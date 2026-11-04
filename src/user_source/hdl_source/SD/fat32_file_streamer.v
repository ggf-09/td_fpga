`timescale 1ns/1ps

module fat32_file_streamer #(
    parameter integer MAX_VISITED_CLUSTERS = 8192,
    parameter integer SEEK_SUPPORT = 0,
    parameter integer RANGE_SUPPORT = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        file_start,
    input  wire [31:0] start_offset,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    output wire        file_busy,
    output reg         file_done,
    output reg         file_valid,
    output reg  [7:0]  file_byte,
    output reg  [31:0] file_byte_offset,
    output reg  [7:0]  fs_error,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error,
    input  wire        file_partial
);
    localparam ERR_NONE              = 8'h00;
    localparam ERR_SECTOR            = 8'h10;
    localparam ERR_FAT_LOOP          = 8'h23;
    localparam ERR_CLUSTER_RANGE     = 8'h24;
    localparam ERR_EARLY_EOF         = 8'h25;
    localparam ERR_VISITED_EXHAUSTED = 8'h26;

    localparam ST_IDLE       = 4'd0;
    localparam ST_DATA_REQ   = 4'd1;
    localparam ST_DATA_WAIT  = 4'd2;
    localparam ST_FAT_REQ    = 4'd3;
    localparam ST_FAT_WAIT   = 4'd4;
    localparam ST_FAT_PARSE  = 4'd5;
    localparam ST_LBA_MUL    = 4'd6;
    localparam ST_FINISH     = 4'd7;
    localparam ST_LBA_ADD    = 4'd8;
    localparam ST_DATA_FINISH = 4'd9;
    localparam ST_START_CHECK = 4'd10;
    localparam ST_SEEK_CLUSTER = 4'd11;
    localparam ST_LBA_SECTOR = 4'd12;
    localparam ST_FAT_CHECK = 4'd13;
    reg fat_eoc,fat_small,fat_hi_gt,fat_hi_eq,fat_lo_gt,fat_same,fat_limit;
    wire fat_bad=fat_small || fat_hi_gt || (fat_hi_eq && fat_lo_gt);
    reg partial_q;
    reg [31:0] skip_bytes;
    reg [8:0] prefix_bytes;

    localparam integer CHAIN_COUNT_WIDTH = $clog2(MAX_VISITED_CLUSTERS + 1);

    reg [3:0] state;
    reg [31:0] current_cluster;
    reg [31:0] next_cluster;
    reg [31:0] remaining_bytes;
    reg [7:0] sector_in_cluster;
    reg [8:0] fat_entry_offset;
    reg [7:0] fat_byte0, fat_byte1, fat_byte2, fat_byte3;
    reg [CHAIN_COUNT_WIDTH-1:0] chain_count;
    reg final_chain_check;
    reg [31:0] cluster_index;
    reg [31:0] cluster_sector_offset;
    // Geometry is fixed for one file. Register it at the start so the
    // cluster-address multiplier does not depend on the root scanner's
    // long decode path while streaming.
    reg [7:0] file_spc;
    wire [31:0] cluster_bytes={15'd0,file_spc,9'd0};
    reg [7:0] last_sector_error;
    reg start_empty,start_bad;
    reg start_hi_gt,start_hi_eq,start_lo_gt,offset_hi_gt,offset_hi_eq,offset_lo_ge;

    assign file_busy = (state != ST_IDLE);

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    task advance_to_next_cluster;
        input [31:0] cluster_value;
        begin
            chain_count <= chain_count + 1'b1;
            current_cluster <= cluster_value;
            cluster_index <= cluster_value - 2;
            state <= SEEK_SUPPORT!=0 ? ST_SEEK_CLUSTER : ST_LBA_MUL;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            partial_q <= 0;
            file_done <= 1'b0;
            file_valid <= 1'b0;
            file_byte <= 8'd0;
            file_byte_offset <= 32'd0;
            fs_error <= ERR_NONE;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            current_cluster <= 32'd0;
            next_cluster <= 32'd0;
            remaining_bytes <= 32'd0;
            sector_in_cluster <= 8'd0;
            fat_entry_offset <= 9'd0;
            fat_byte0 <= 8'd0;
            fat_byte1 <= 8'd0;
            fat_byte2 <= 8'd0;
            fat_byte3 <= 8'd0;
            chain_count <= 0;
            final_chain_check <= 1'b0;
            cluster_index <= 32'd0;
            cluster_sector_offset <= 32'd0;
            file_spc <= 8'd0;
            last_sector_error <= 8'd0;
            start_empty<=0;start_bad<=0;start_hi_gt<=0;start_hi_eq<=0;start_lo_gt<=0;
            offset_hi_gt<=0;offset_hi_eq<=0;offset_lo_ge<=0;skip_bytes<=0;prefix_bytes<=0;
            fat_eoc<=0;fat_small<=0;fat_hi_gt<=0;fat_hi_eq<=0;fat_lo_gt<=0;fat_same<=0;fat_limit<=0;
        end else begin
            file_done <= 1'b0;
            file_valid <= 1'b0;
            sector_req <= 1'b0;

            if (state == ST_DATA_WAIT && sector_valid && remaining_bytes != 0) begin
                file_valid <= SEEK_SUPPORT==0 || sector_byte_index>=prefix_bytes;
                file_byte <= sector_byte;
                file_byte_offset <= file_size - remaining_bytes;
                remaining_bytes <= remaining_bytes - 1'b1;
            end

            if (state == ST_FAT_WAIT && sector_valid) begin
                if (sector_byte_index == fat_entry_offset)
                    fat_byte0 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 1'b1)
                    fat_byte1 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd2)
                    fat_byte2 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd3)
                    fat_byte3 <= sector_byte;
            end

            case (state)
                ST_IDLE: if (file_start) begin
                    partial_q <= RANGE_SUPPORT != 0 && file_partial === 1'b1;
                    file_spc <= sectors_per_cluster;
                    fs_error <= ERR_NONE;
                    file_byte_offset <= 32'd0;
                    remaining_bytes <= SEEK_SUPPORT!=0 ? file_size-{start_offset[31:9],9'd0} : file_size;
                    sector_in_cluster <= 8'd0;
                    chain_count <= 1;
                    final_chain_check <= 1'b0;
                    current_cluster<=first_cluster;
                    start_empty<=file_size==0;
                    start_bad<=first_cluster<2 || sectors_per_cluster==0;
                    start_hi_gt<=first_cluster[31:16]>max_cluster[31:16];
                    start_hi_eq<=first_cluster[31:16]==max_cluster[31:16];
                    start_lo_gt<=first_cluster[15:0]>max_cluster[15:0];
                    offset_hi_gt<=SEEK_SUPPORT!=0 && start_offset[31:16]>file_size[31:16];
                    offset_hi_eq<=SEEK_SUPPORT!=0 && start_offset[31:16]==file_size[31:16];
                    offset_lo_ge<=SEEK_SUPPORT!=0 && start_offset[15:0]>=file_size[15:0];
                    skip_bytes<=SEEK_SUPPORT!=0 ? {start_offset[31:9],9'd0} : 0;
                    prefix_bytes<=SEEK_SUPPORT!=0 ? start_offset[8:0] : 0;
                    state<=ST_START_CHECK;
                end
                // Snapshot the file descriptor before its range check drives
                // the multiplier and cluster-register enables.
                ST_START_CHECK: begin
                    cluster_index<=current_cluster-2;
                    if (start_empty) begin
                        state <= ST_FINISH;
                    end else if (start_bad || start_hi_gt || (start_hi_eq && start_lo_gt) ||
                                 offset_hi_gt || (offset_hi_eq && offset_lo_ge)) begin
                        finish_with_error(ERR_CLUSTER_RANGE);
                    end else begin
                        state <= SEEK_SUPPORT!=0 ? ST_SEEK_CLUSTER : ST_LBA_MUL;
                    end
                end
                ST_SEEK_CLUSTER: begin
                    if(skip_bytes>=cluster_bytes)begin
                        skip_bytes<=skip_bytes-cluster_bytes;
                        fat_entry_offset<={current_cluster[6:0],2'b00};
                        sector_lba<=fat_start_lba+(current_cluster>>7);
                        state<=ST_FAT_REQ;
                    end else begin
                        sector_in_cluster<=skip_bytes[16:9];
                        skip_bytes<=0;
                        state<=ST_LBA_MUL;
                    end
                end
                // 将簇号换算成 LBA 拆成乘法、加法两拍，避免 100 MHz 下
                // “减法 + 乘法 + 加法”形成一条过长组合路径。
                ST_LBA_MUL: begin
                    cluster_sector_offset <= cluster_index * file_spc;
                    state <= ST_LBA_ADD;
                end
                ST_LBA_ADD: begin
                    sector_lba <= data_start_lba + cluster_sector_offset;
                    state <= SEEK_SUPPORT!=0 ? ST_LBA_SECTOR : ST_DATA_REQ;
                end
                ST_LBA_SECTOR: begin
                    sector_lba<=sector_lba+sector_in_cluster;
                    state<=ST_DATA_REQ;
                end
                ST_DATA_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_DATA_WAIT;
                end
                ST_DATA_WAIT: if (sector_done) begin
                    last_sector_error <= sector_error;
                    state <= ST_DATA_FINISH;
                end
                ST_DATA_FINISH: begin
                    prefix_bytes<=0;
                    if (last_sector_error != 0) begin
                        finish_with_error(ERR_SECTOR);
                    end else if (remaining_bytes == 0 && partial_q) begin
                        // A bounded font window ends inside a valid larger file.
                        // The current physical sector has completely drained.
                        state <= ST_FINISH;
                    end else if (remaining_bytes == 0) begin
                        final_chain_check <= 1'b1;
                        sector_in_cluster <= 8'd0;
                        fat_entry_offset <= {current_cluster[6:0], 2'b00};
                        sector_lba <= fat_start_lba + (current_cluster >> 7);
                        state <= ST_FAT_REQ;
                    end else if (sector_in_cluster + 1'b1 < file_spc) begin
                        sector_in_cluster <= sector_in_cluster + 1'b1;
                        sector_lba <= sector_lba + 1'b1;
                        state <= ST_DATA_REQ;
                    end else begin
                        sector_in_cluster <= 8'd0;
                        fat_entry_offset <= {current_cluster[6:0], 2'b00};
                        sector_lba <= fat_start_lba + (current_cluster >> 7);
                        state <= ST_FAT_REQ;
                    end
                end
                ST_FAT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_FAT_WAIT;
                end
                ST_FAT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else
                        state <= ST_FAT_PARSE;
                end
                // Separate FAT range comparisons from the state/counter enables.
                // The byte registers remain stable until the next FAT request.
                ST_FAT_PARSE: begin
                    fat_eoc<={fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0}>=28'hffffff8;
                    fat_small<={4'd0,fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0}<2;
                    fat_hi_gt<={4'd0,fat_byte3[3:0],fat_byte2}>max_cluster[31:16];
                    fat_hi_eq<={4'd0,fat_byte3[3:0],fat_byte2}==max_cluster[31:16];
                    fat_lo_gt<={fat_byte1,fat_byte0}>max_cluster[15:0];
                    fat_same<={4'd0,fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0}==current_cluster;
                    fat_limit<=chain_count>=MAX_VISITED_CLUSTERS;
                    state<=ST_FAT_CHECK;
                end
                ST_FAT_CHECK: begin
                    if(final_chain_check)begin
                        final_chain_check<=0;
                        if(fat_eoc)state<=ST_FINISH;
                        else if(fat_bad)finish_with_error(ERR_CLUSTER_RANGE);
                        else finish_with_error(ERR_FAT_LOOP);
                    end else if(fat_eoc)finish_with_error(ERR_EARLY_EOF);
                    else if(fat_bad)finish_with_error(ERR_CLUSTER_RANGE);
                    else if(fat_limit)finish_with_error(ERR_VISITED_EXHAUSTED);
                    else if(fat_same)finish_with_error(ERR_FAT_LOOP);
                    else advance_to_next_cluster({4'd0,fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0});
                end
                ST_FINISH: begin
                    file_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
