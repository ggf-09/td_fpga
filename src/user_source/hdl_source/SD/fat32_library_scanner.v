`timescale 1ns/1ps

module fat32_library_scanner #(parameter integer MAX_ROOT_SECTORS=256) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    input  wire        page_start,
    input  wire [1:0]  page_select,
    output wire [1:0]  loaded_page,
    output reg  [15:0] library_bmp_valid,library_song_valid,library_lrc_valid,
    output reg [1:0] checkpoint_valid,
    output reg [31:0] checkpoint_a_cluster,checkpoint_b_cluster,
    output reg menu_valid,
    output reg [31:0] menu_cluster,menu_size,
    output wire        scan_busy,
    output reg         scan_done,
    output reg  [7:0]  fs_error,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [3:0]  resource_valid,
    output reg  [31:0] resource0_cluster,
    output reg  [31:0] resource1_cluster,
    output reg  [31:0] resource2_cluster,
    output reg  [31:0] resource3_cluster,
    output reg  [31:0] resource0_size,
    output reg  [31:0] resource1_size,
    output reg  [31:0] resource2_size,
    output reg  [31:0] resource3_size,
    output reg  [3:0]  song_valid,
    output reg  [31:0] song0_cluster,
    output reg  [31:0] song1_cluster,
    output reg  [31:0] song2_cluster,
    output reg  [31:0] song3_cluster,
    output reg  [31:0] song0_size,
    output reg  [31:0] song1_size,
    output reg  [31:0] song2_size,
    output reg  [31:0] song3_size,
    output reg  [3:0]  lrc_valid,
    output reg  [31:0] lrc0_cluster,
    output reg  [31:0] lrc1_cluster,
    output reg  [31:0] lrc2_cluster,
    output reg  [31:0] lrc3_cluster,
    output reg  [31:0] lrc0_size,
    output reg  [31:0] lrc1_size,
    output reg  [31:0] lrc2_size,
    output reg  [31:0] lrc3_size,
    output reg         font_valid,
    output reg  [31:0] font_cluster,
    output reg  [31:0] font_size,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

    localparam ERR_NONE            = 8'h00;
    localparam ERR_SECTOR          = 8'h10;
    localparam ERR_BOOT_SIGNATURE  = 8'h20;
    localparam ERR_UNSUPPORTED_BPB = 8'h21;
    localparam ERR_RESOURCE_MISSING= 8'h22;

    localparam ST_IDLE       = 4'd0;
    localparam ST_READ0_REQ  = 4'd1;
    localparam ST_READ0_WAIT = 4'd2;
    localparam ST_BOOT_PARSE = 4'd3;
    localparam ST_BOOT_REQ   = 4'd4;
    localparam ST_BOOT_WAIT  = 4'd5;
    localparam ST_ROOT_REQ   = 4'd6;
    localparam ST_ROOT_WAIT  = 4'd7;
    localparam ST_DIR_SCAN   = 4'd8;
    localparam ST_FINISH     = 4'd9;
    localparam ST_BOOT_LAYOUT= 4'd10;
    localparam ST_BOOT_ROOT  = 4'd11;

    localparam ST_CLEAR=12,ST_FAT_REQ=13,ST_FAT_WAIT=14,
               ST_PAGE_ISSUE=15,ST_PAGE_WAIT=16,ST_PAGE_STORE=17,
               ST_ADDRESS_BASE=18,ST_ADDRESS_SHIFT=19,ST_ADDRESS_ADD=20,ST_CHAIN_CHECK=21,ST_BOOT_CHECK=22;
    reg [4:0] state;
    reg [15:0] catalog [0:255];
    reg [7:0] clear_addr,cat_waddr,cat_raddr;
    reg [31:0] cat_cluster,cat_size;
    reg [15:0] cat_q,cat_low;
    (* keep = "true" *) reg [23:0] page_write_q;
    reg read_half;
    wire [31:0] cat_read_word={cat_q,cat_low};
    reg [2:0] cat_pending;
    reg [4:0] page_word;
    reg [1:0] selected_page;
    reg [15:0] root_sectors_seen;
    reg [31:0] chain_next;
    reg chain_eoc,chain_small,chain_hi_gt,chain_hi_eq,chain_lo_gt,chain_same,chain_io_error,boot_bad;
    wire chain_large=chain_hi_gt || (chain_hi_eq && chain_lo_gt);
    reg directory_end;
    reg [7:0] root_last_sector;
    reg [31:0] root_delta,root_displacement,root_fat_sector,root_fat_lba,max_cluster_raw;
    wire [8:0] chain_offset;
    always @(posedge clk) begin
        if(state==ST_CLEAR) catalog[clear_addr]<=0;
        else if(cat_pending!=0) catalog[cat_waddr]<=cat_pending==4?cat_cluster[15:0]:
            cat_pending==3?cat_cluster[31:16]:cat_pending==2?cat_size[15:0]:cat_size[31:16];
        cat_q<=catalog[cat_raddr];
    end
    reg [7:0] sector_buffer [0:511];
    reg [4:0] directory_entry_index;
    reg [7:0] root_sector_index;
    reg [31:0] root_cluster;
    assign chain_offset={root_cluster[6:0],2'b00};
    reg [31:0] total_sectors;
    reg [31:0] fat_sectors;
    reg [7:0] fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] root_lba;
    reg [31:0] data_sector_count;
    reg [31:0] fat_span;
    reg [2:0] sectors_per_cluster_shift;
    reg [7:0] dir_name0;
    reg [7:0] dir_name1;
    reg [7:0] dir_name2;
    reg [7:0] dir_name3;
    reg [7:0] dir_name4;
    reg [7:0] dir_name5;
    reg [7:0] dir_name6;
    reg [7:0] dir_name7;
    reg [7:0] dir_name8;
    reg [7:0] dir_name9;
    reg [7:0] dir_name10;
    reg       dir_entry_match;
    reg       dir_entry_song;
    reg       dir_entry_lrc;
    reg       dir_entry_font;
    reg       dir_entry_menu;
    reg dir_checkpoint,dir_checkpoint_slot;
    reg [3:0] dir_resource_index;
    reg [15:0] dir_cluster_high;
    reg [15:0] dir_cluster_low;
    reg [31:0] dir_file_size;
    // Cluster bytes are complete at directory byte 27; use registered halves
    // at byte 31 so the checkpoint bound check is not one long 32-bit path.
    reg ck_cluster_small,ck_cluster_hi_lt,ck_cluster_hi_eq,ck_cluster_lo_le;
    always @(posedge clk)begin
        ck_cluster_small<=({dir_cluster_high,dir_cluster_low}<2);
        ck_cluster_hi_lt<=dir_cluster_high<max_cluster[31:16];
        ck_cluster_hi_eq<=dir_cluster_high==max_cluster[31:16];
        ck_cluster_lo_le<=dir_cluster_low<=max_cluster[15:0];
    end
    // FAT regular files may carry any read-only/hidden/system/archive flags.
    // Exclude directories and volume labels (also excludes LFN entries).
    wire regular_file_attr = (sector_byte & 8'h18) == 0;

    assign loaded_page=selected_page;
    assign scan_busy = (state != ST_IDLE);

    function [15:0] le16;
        input integer offset;
        begin
            le16 = {sector_buffer[offset+1], sector_buffer[offset]};
        end
    endfunction

    function [31:0] le32;
        input integer offset;
        begin
            le32 = {sector_buffer[offset+3], sector_buffer[offset+2],
                    sector_buffer[offset+1], sector_buffer[offset]};
        end
    endfunction

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = value != 0 && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    function [4:0] track_number;
        input [7:0] first,second;
        begin
            if(first>="1" && first<="9" && second==" ") track_number=first-"0";
            else if(first=="1" && second>="0" && second<="6") track_number=10+second-"0";
            else track_number=0;
        end
    endfunction
    reg [4:0] pic_number, song_number;
    function [1:0] first_page;
        input [15:0] mask;
        begin
            if(mask[3:0]!=0)first_page=0;
            else if(mask[7:4]!=0)first_page=1;
            else if(mask[11:8]!=0)first_page=2;
            else first_page=3;
        end
    endfunction
    wire [6:0] page_address={selected_page,page_word[2:1],page_word[4:3],page_word[0]};
    // page_word is {kind[1:0],slot[1:0],half}; kind 0=BMP,1=WAV,2=LRC.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            library_bmp_valid<=0;library_song_valid<=0;library_lrc_valid<=0;
            clear_addr<=0;cat_waddr<=0;cat_raddr<=0;cat_pending<=0;
            cat_cluster<=0;cat_size<=0;page_word<=0;selected_page<=0;
            cat_low<=0;read_half<=0;page_write_q<=0;
            root_sectors_seen<=0;chain_next<=0;chain_eoc<=0;chain_small<=0;chain_hi_gt<=0;chain_hi_eq<=0;chain_lo_gt<=0;boot_bad<=0;chain_same<=0;chain_io_error<=0;directory_end<=0;root_last_sector<=0;
            root_delta<=0;root_displacement<=0;root_fat_sector<=0;root_fat_lba<=0;max_cluster_raw<=0;
            scan_done <= 1'b0;
            fs_error <= ERR_NONE;
            partition_lba <= 32'd0;
            sectors_per_cluster <= 8'd0;
            fat_start_lba <= 32'd0;
            data_start_lba <= 32'd0;
            max_cluster <= 32'd0;
            resource_valid <= 4'd0;
            resource0_cluster <= 32'd0;
            resource1_cluster <= 32'd0;
            resource2_cluster <= 32'd0;
            resource3_cluster <= 32'd0;
            resource0_size <= 32'd0;
            resource1_size <= 32'd0;
            resource2_size <= 32'd0;
            resource3_size <= 32'd0;
            song_valid <= 4'd0;
            song0_cluster <= 32'd0;
            song1_cluster <= 32'd0;
            song2_cluster <= 32'd0;
            song3_cluster <= 32'd0;
            song0_size <= 32'd0;
            song1_size <= 32'd0;
            song2_size <= 32'd0;
            song3_size <= 32'd0;
            lrc_valid <= 4'd0;
            lrc0_cluster <= 0; lrc1_cluster <= 0;
            lrc2_cluster <= 0; lrc3_cluster <= 0;
            lrc0_size <= 0; lrc1_size <= 0;
            lrc2_size <= 0; lrc3_size <= 0;
            font_valid <= 1'b0;
            checkpoint_valid<=0;checkpoint_a_cluster<=0;checkpoint_b_cluster<=0;dir_checkpoint<=0;dir_checkpoint_slot<=0;
            menu_valid <= 0;menu_cluster <= 0;menu_size <= 0;
            font_cluster <= 0; font_size <= 0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            directory_entry_index <= 5'd0;
            root_sector_index <= 4'd0;
            root_cluster <= 32'd0;
            total_sectors <= 32'd0;
            fat_sectors <= 32'd0;
            fat_count <= 8'd0;
            reserved_sectors <= 16'd0;
            root_lba <= 32'd0;
            data_sector_count <= 32'd0;
            fat_span <= 32'd0;
            sectors_per_cluster_shift <= 3'd0;
            dir_name0 <= 8'd0;
            dir_name1 <= 8'd0;
            dir_name2 <= 8'd0;
            dir_name3 <= 8'd0;
            dir_name4 <= 8'd0;
            dir_name5 <= 8'd0;
            dir_name6 <= 8'd0;
            dir_name7 <= 8'd0;
            dir_name8 <= 8'd0;
            dir_name9 <= 8'd0;
            dir_name10 <= 8'd0;
            pic_number <= 0; song_number <= 0;
            dir_entry_match <= 1'b0;
            dir_entry_song <= 1'b0;
            dir_entry_lrc <= 1'b0;
            dir_entry_font <= 1'b0;dir_entry_menu <= 0;
            dir_resource_index <= 2'd3;
            dir_cluster_high <= 16'd0;
            dir_cluster_low <= 16'd0;
            dir_file_size <= 32'd0;
        end else begin
            scan_done <= 1'b0;
            sector_req <= 1'b0;
            page_write_q <= state==ST_PAGE_WAIT && read_half ? (24'b1<<page_word) : 24'd0;
            if (sector_valid && state != ST_ROOT_WAIT)
                sector_buffer[sector_byte_index] <= sector_byte;

            if (sector_valid && state == ST_ROOT_WAIT && !directory_end) begin
                case (sector_byte_index[4:0])
                    5'd0: begin
                        dir_checkpoint<=0;
                        dir_name0 <= sector_byte;
                        if(sector_byte==0) directory_end<=1;
                        dir_entry_match <= 1'b0;
                        dir_entry_song <= 1'b0;
                        dir_entry_lrc <= 1'b0;
                        dir_entry_font <= 1'b0;dir_entry_menu <= 0;
                    end
                    5'd1:  dir_name1 <= sector_byte;
                    5'd2:  dir_name2 <= sector_byte;
                    5'd3:  dir_name3 <= sector_byte;
                    5'd4:  dir_name4 <= sector_byte;
                    5'd5:  dir_name5 <= sector_byte;
                    5'd6: begin
                        dir_name6 <= sector_byte;
                        // Digits 3..5 arrived before byte 6. Decode here,
                        // ahead of the attribute/type decision at byte 11.
                        pic_number <= track_number(dir_name3,dir_name4);
                        song_number <= track_number(dir_name4,dir_name5);
                    end
                    5'd7:  dir_name7 <= sector_byte;
                    5'd8:  dir_name8 <= sector_byte;
                    5'd9:  dir_name9 <= sector_byte;
                    5'd10: dir_name10 <= sector_byte;
                    5'd11: begin
                        if ((sector_byte & 8'h19)==0 && dir_name0=="R" && dir_name1=="E" &&
                            dir_name2=="S" && dir_name3=="U" && dir_name4=="M" &&
                            (dir_name5=="A" || dir_name5=="B") && dir_name6==" " &&
                            dir_name7==" " && dir_name8=="B" && dir_name9=="I" && dir_name10=="N")begin
                            dir_checkpoint<=1;dir_checkpoint_slot<=dir_name5=="B";
                        end
                        if (regular_file_attr &&
                            dir_name0 == "P" && dir_name1 == "I" &&
                            dir_name2 == "C" && pic_number != 0 &&
                            dir_name5 == " " && dir_name6 == " " &&
                            dir_name7 == " " && dir_name8 == "B" &&
                            dir_name9 == "M" && dir_name10 == "P") begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= pic_number - 1'b1;
                        end else if (regular_file_attr &&
                            dir_name0 == "S" && dir_name1 == "O" &&
                            dir_name2 == "N" && dir_name3 == "G" &&
                            song_number != 0 && dir_name6 == " " &&
                            dir_name7 == " " && dir_name8 == "W" &&
                            dir_name9 == "A" && dir_name10 == "V") begin
                            dir_entry_song <= 1'b1;
                            dir_resource_index <= song_number - 1'b1;
                        end else if (regular_file_attr &&
                            dir_name0 == "S" && dir_name1 == "O" &&
                            dir_name2 == "N" && dir_name3 == "G" &&
                            song_number != 0 && dir_name6 == " " &&
                            dir_name7 == " " && dir_name8 == "L" &&
                            dir_name9 == "R" && dir_name10 == "C") begin
                            dir_entry_lrc <= 1'b1;
                            dir_resource_index <= song_number - 1'b1;
                        end else if (regular_file_attr &&
                            dir_name0 == "M" && dir_name1 == "E" &&
                            dir_name2 == "N" && dir_name3 == "U" &&
                            dir_name4 == " " && dir_name5 == " " &&
                            dir_name6 == " " && dir_name7 == " " &&
                            dir_name8 == "B" && dir_name9 == "M" && dir_name10 == "P") begin
                            dir_entry_menu <= 1'b1;
                        end else if (regular_file_attr &&
                            dir_name0 == "F" && dir_name1 == "O" &&
                            dir_name2 == "N" && dir_name3 == "T" &&
                            dir_name4 == " " && dir_name5 == " " &&
                            dir_name6 == " " && dir_name7 == " " &&
                            dir_name8 == "B" && dir_name9 == "I" &&
                            dir_name10 == "N") begin
                            dir_entry_font <= 1'b1;
                        end
                    end
                    5'd20: dir_cluster_high[7:0] <= sector_byte;
                    5'd21: dir_cluster_high[15:8] <= sector_byte;
                    5'd26: dir_cluster_low[7:0] <= sector_byte;
                    5'd27: dir_cluster_low[15:8] <= sector_byte;
                    5'd28: dir_file_size[7:0] <= sector_byte;
                    5'd29: dir_file_size[15:8] <= sector_byte;
                    5'd30: dir_file_size[23:16] <= sector_byte;
                    5'd31: begin
                        dir_file_size[31:24] <= sector_byte;
                        if(dir_checkpoint && {sector_byte,dir_file_size[23:0]}==512 &&
                           !ck_cluster_small &&
                           (ck_cluster_hi_lt || (ck_cluster_hi_eq && ck_cluster_lo_le)))begin
                            checkpoint_valid[dir_checkpoint_slot]<=1;
                            if(dir_checkpoint_slot)checkpoint_b_cluster<={dir_cluster_high,dir_cluster_low};
                            else checkpoint_a_cluster<={dir_cluster_high,dir_cluster_low};
                        end
                        if (dir_entry_match || dir_entry_song || dir_entry_lrc) begin
                            cat_cluster<={dir_cluster_high,dir_cluster_low};
                            cat_size<={sector_byte,dir_file_size[23:0]};
                            cat_waddr<={dir_resource_index,
                                (dir_entry_match?2'd0:dir_entry_song?2'd1:2'd2),2'b00};
                            cat_pending<=4;
                            if(dir_entry_match && {sector_byte,dir_file_size[23:0]}!=0)
                                library_bmp_valid[dir_resource_index]<=1;
                            if(dir_entry_song && {sector_byte,dir_file_size[23:0]}>=44)
                                library_song_valid[dir_resource_index]<=1;
                            if(dir_entry_lrc && {sector_byte,dir_file_size[23:0]}!=0)
                                library_lrc_valid[dir_resource_index]<=1;
                        end else if (dir_entry_menu) begin
                            menu_cluster<={dir_cluster_high,dir_cluster_low};
                            menu_size<={sector_byte,dir_file_size[23:0]};
                            menu_valid<={sector_byte,dir_file_size[23:0]}>=32'd54;
                        end else if (dir_entry_font &&
                                     {sector_byte, dir_file_size[23:0]} >= 32'd8) begin
                            font_cluster <= {dir_cluster_high, dir_cluster_low};
                            font_size <= {sector_byte, dir_file_size[23:0]};
                            font_valid <= 1'b1;
                        end
                    end
                    default: begin end
                endcase
            end

            if(cat_pending!=0) begin
                cat_pending<=cat_pending-1'b1;
                cat_waddr<=cat_waddr+1'b1;
            end
            if(state==ST_FAT_WAIT && sector_valid) begin
                if(sector_byte_index==chain_offset) chain_next[7:0]<=sector_byte;
                if(sector_byte_index==chain_offset+1) chain_next[15:8]<=sector_byte;
                if(sector_byte_index==chain_offset+2) chain_next[23:16]<=sector_byte;
                if(sector_byte_index==chain_offset+3) chain_next[31:24]<=sector_byte;
            end
            case (state)
                ST_IDLE: if (scan_start) begin
                    fs_error <= ERR_NONE;
                    partition_lba <= 32'd0;
                    resource_valid <= 4'd0;
                    song_valid <= 4'd0;
                    lrc_valid <= 4'd0;
                    checkpoint_valid<=0;
                    font_valid <= 1'b0;menu_valid<=0;
                    root_sector_index <= 4'd0;
                    library_bmp_valid<=0;library_song_valid<=0;library_lrc_valid<=0;
                    clear_addr<=0;selected_page<=page_select;root_sectors_seen<=0;
                    directory_end<=0;state<=ST_CLEAR;
                end
                else if(page_start) begin
                    selected_page<=page_select;page_word<=0;state<=ST_PAGE_ISSUE;
                end
                ST_CLEAR: if(clear_addr==255) state<=ST_READ0_REQ;
                          else clear_addr<=clear_addr+1'b1;
                ST_READ0_REQ: if (!sector_busy) begin
                    sector_lba <= 32'd0;
                    sector_req <= 1'b1;
                    state <= ST_READ0_WAIT;
                end
                ST_READ0_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (sector_buffer[510] != 8'h55 || sector_buffer[511] != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else if (sector_buffer[0] == 8'heb || sector_buffer[0] == 8'he9) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
                    end else if (sector_buffer[450] == 8'h0b || sector_buffer[450] == 8'h0c) begin
                        partition_lba <= le32(454);
                        sector_lba <= le32(454);
                        state <= ST_BOOT_REQ;
                    end else begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end
                end
                ST_BOOT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_BOOT_WAIT;
                end
                ST_BOOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (sector_buffer[510] != 8'h55 || sector_buffer[511] != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else
                        state <= ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE: begin
                    boot_bad<=(le16(11) != 16'd512 || !valid_spc(sector_buffer[13]) ||
                        le16(14) == 0 || (sector_buffer[16] != 1 && sector_buffer[16] != 2) ||
                        le16(17) != 0 || le16(22) != 0 || le32(32) == 0 ||
                        le32(36) == 0 || le32(44) < 2);
                    state<=ST_BOOT_CHECK;
                end
                ST_BOOT_CHECK: begin
                    if(boot_bad)finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin
                        sectors_per_cluster <= sector_buffer[13];
                        root_last_sector<=sector_buffer[13]-8'd1;
                        reserved_sectors <= le16(14);
                        fat_count <= sector_buffer[16];
                        total_sectors <= le32(32);
                        fat_sectors <= le32(36);
                        root_cluster <= le32(44);
                        sectors_per_cluster_shift <= spc_shift(sector_buffer[13]);
                        fat_span <= sector_buffer[16] == 2 ? (le32(36) << 1) : le32(36);
                        fat_start_lba <= partition_lba + le16(14);
                        state <= ST_BOOT_LAYOUT;
                    end
                end
                ST_BOOT_LAYOUT: begin
                    data_start_lba <= partition_lba + reserved_sectors + fat_span;
                    data_sector_count <= total_sectors - reserved_sectors - fat_span;
                    state <= ST_BOOT_ROOT;
                end
                ST_BOOT_ROOT: begin
                    max_cluster_raw<=data_sector_count>>sectors_per_cluster_shift;
                    state<=ST_ADDRESS_BASE;
                end
                ST_ADDRESS_BASE: begin
                    max_cluster<=max_cluster_raw+1'b1;
                    root_delta<=root_cluster-2;
                    root_fat_sector<=root_cluster>>7;
                    state<=ST_ADDRESS_SHIFT;
                end
                ST_ADDRESS_SHIFT: begin
                    root_displacement<=root_delta<<sectors_per_cluster_shift;
                    root_fat_lba<=fat_start_lba+root_fat_sector;
                    state<=ST_ADDRESS_ADD;
                end
                ST_ADDRESS_ADD: begin
                    sector_lba<=data_start_lba+root_displacement;
                    root_sector_index<=0;state<=ST_ROOT_REQ;
                end
                ST_ROOT_REQ: if (!sector_busy) begin
                    dir_entry_match <= 1'b0;
                    dir_entry_song <= 1'b0;
                    dir_entry_lrc <= 1'b0;
                    dir_entry_font <= 1'b0;dir_entry_menu <= 0;
                    sector_req <= 1'b1;
                    state <= ST_ROOT_WAIT;
                end
                ST_ROOT_WAIT: if (sector_done) begin
                    root_sectors_seen<=root_sectors_seen+1'b1;
                    if(sector_error!=0) finish_with_error(ERR_SECTOR);
                    else if(directory_end) begin
                        selected_page<=first_page(library_bmp_valid&library_song_valid);
                        page_word<=0;state<=ST_PAGE_ISSUE;
                    end
                    else if(root_sectors_seen>=MAX_ROOT_SECTORS-1) finish_with_error(8'h23);
                    else if(root_sector_index!=root_last_sector) begin
                        root_sector_index<=root_sector_index+1'b1;
                        sector_lba<=sector_lba+1'b1;state<=ST_ROOT_REQ;
                    end else begin
                        sector_lba<=root_fat_lba;chain_next<=0;state<=ST_FAT_REQ;
                    end
                end
                ST_FAT_REQ: if(!sector_busy) begin sector_req<=1;state<=ST_FAT_WAIT;end
                ST_FAT_WAIT: if(sector_done) begin
                    chain_io_error<=sector_error!=0;
                    chain_eoc<=chain_next[27:0]>=28'hffffff8;
                    chain_small<=chain_next[27:0]<2;
                    chain_hi_gt<={4'd0,chain_next[27:16]}>max_cluster[31:16];
                    chain_hi_eq<={4'd0,chain_next[27:16]}==max_cluster[31:16];
                    chain_lo_gt<=chain_next[15:0]>max_cluster[15:0];
                    chain_same<=chain_next[27:0]==root_cluster;
                    state<=ST_CHAIN_CHECK;
                end
                ST_CHAIN_CHECK: begin
                    if(chain_io_error)finish_with_error(ERR_SECTOR);
                    else if(chain_eoc)begin
                        selected_page<=first_page(library_bmp_valid&library_song_valid);
                        page_word<=0;state<=ST_PAGE_ISSUE;
                    end else if(chain_small || chain_large || chain_same)finish_with_error(8'h23);
                    else begin root_cluster<={4'd0,chain_next[27:0]};state<=ST_ADDRESS_BASE;end
                end
                ST_PAGE_ISSUE: begin
                    if((library_bmp_valid&library_song_valid)==0)fs_error<=ERR_RESOURCE_MISSING;
                    cat_raddr<={page_address,read_half};state<=ST_PAGE_WAIT;
                    resource_valid<=(library_bmp_valid>>(selected_page*4));
                    song_valid<=(library_song_valid>>(selected_page*4));
                    lrc_valid<=(library_lrc_valid>>(selected_page*4));
                end
                ST_PAGE_WAIT: state<=ST_PAGE_STORE;
                ST_PAGE_STORE: begin
                    if(!read_half)begin cat_low<=cat_q;read_half<=1;state<=ST_PAGE_ISSUE;end
                    else begin
                    read_half<=0;
                    if(page_write_q[0]) resource0_cluster<=cat_read_word;
                    if(page_write_q[1]) resource0_size<=cat_read_word;
                    if(page_write_q[2]) resource1_cluster<=cat_read_word;
                    if(page_write_q[3]) resource1_size<=cat_read_word;
                    if(page_write_q[4]) resource2_cluster<=cat_read_word;
                    if(page_write_q[5]) resource2_size<=cat_read_word;
                    if(page_write_q[6]) resource3_cluster<=cat_read_word;
                    if(page_write_q[7]) resource3_size<=cat_read_word;
                    if(page_write_q[8]) song0_cluster<=cat_read_word;
                    if(page_write_q[9]) song0_size<=cat_read_word;
                    if(page_write_q[10]) song1_cluster<=cat_read_word;
                    if(page_write_q[11]) song1_size<=cat_read_word;
                    if(page_write_q[12]) song2_cluster<=cat_read_word;
                    if(page_write_q[13]) song2_size<=cat_read_word;
                    if(page_write_q[14]) song3_cluster<=cat_read_word;
                    if(page_write_q[15]) song3_size<=cat_read_word;
                    if(page_write_q[16]) lrc0_cluster<=cat_read_word;
                    if(page_write_q[17]) lrc0_size<=cat_read_word;
                    if(page_write_q[18]) lrc1_cluster<=cat_read_word;
                    if(page_write_q[19]) lrc1_size<=cat_read_word;
                    if(page_write_q[20]) lrc2_cluster<=cat_read_word;
                    if(page_write_q[21]) lrc2_size<=cat_read_word;
                    if(page_write_q[22]) lrc3_cluster<=cat_read_word;
                    if(page_write_q[23]) lrc3_size<=cat_read_word;
                    if(page_word==23) state<=ST_FINISH;
                    else begin page_word<=page_word+1'b1;state<=ST_PAGE_ISSUE;end
                    end
                end
                ST_FINISH: begin
                    if(fs_error!=0)begin
                        checkpoint_valid<=0;
                        menu_valid<=0;
                        library_bmp_valid<=0;library_song_valid<=0;library_lrc_valid<=0;
                        resource_valid<=0;song_valid<=0;lrc_valid<=0;font_valid<=0;
                    end
                    scan_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
