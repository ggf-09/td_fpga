`timescale 1ns/1ps
// Streaming 24-bit BMP decoder and load-time nearest-neighbor scaler.
// Input and output pixels are in BMP file order (bottom-up).  The existing
// media_frame_loader performs the vertical flip when it writes SDRAM.
module bmp_pic_decoder (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        abort,
    input  wire [31:0] file_size,
    input  wire        byte_valid,
    input  wire [7:0]  byte_in,
    output wire        pixel_valid,
    output wire [23:0] pixel_rgb,
    output reg  [18:0] out_count,
    output wire        scale_complete,
    output reg         header_error,
    output reg  [15:0] src_width_bcd,
    output reg  [15:0] src_height_bcd,
    output reg         dims_valid
);
    localparam [11:0] DST_W = 12'd640;
    localparam [11:0] DST_H = 12'd480;
    localparam [18:0] OUT_WORDS = 19'd307200;

    reg [31:0] byte_count;
    reg [31:0] data_offset;
    reg [7:0]  dib_size_low;
    reg        dib_size_large;
    reg [11:0] source_width;
    reg [11:0] source_height;
    reg        width_large;
    reg        height_large;
    reg        planes_bad;
    reg        bits_per_pixel_bad;
    reg        compression_bad;
    reg        signature_bad;
    reg        header_checked;
    reg        format_bad;
    reg        pixel_region;
    // data_offset is complete by byte 13; header validation is at byte 34.
    // Register this wide comparison before combining the remaining checks.
    reg offset_bad;
    always @(posedge clk or posedge rst)begin
        if(rst || start || abort)offset_bad<=1'b1;
        else offset_bad<=(data_offset < 54) || (data_offset >= file_size);
    end

    reg [1:0]  pad_count;
    reg [1:0]  rgb_byte_count;
    reg [7:0]  rgb_b;
    reg [7:0]  rgb_g;
    reg [11:0] source_col;
    reg [11:0] source_row;
    reg [11:0] x_phase;
    reg [11:0] y_phase;

    wire pixel_byte_valid = byte_valid && header_checked && !format_bad &&
                            pixel_region && (source_row < source_height);

    // Source-driven phases implement exactly sx=floor(ox*W/640) and
    // sy=floor(oy*H/480).  Column/row zero is emitted explicitly.  Thereafter
    // a phase below two destination units marks an output; emission adds the
    // source dimension while every source step subtracts one destination unit.
    wire [12:0] x_sum = {1'b0, x_phase} + {1'b0, source_width};
    wire [12:0] y_sum = {1'b0, y_phase} + {1'b0, source_height};
    wire x_selected = (source_col == 0) || (x_phase < 13'd1280);
    wire y_selected = (source_row == 0) || (y_phase < 13'd960);
    wire row_emit = y_selected && (out_count < OUT_WORDS);

    assign pixel_valid = pixel_byte_valid && (pad_count == 0) &&
                         (rgb_byte_count == 2) && row_emit && x_selected;
    assign pixel_rgb = {byte_in, rgb_g, rgb_b};
    assign scale_complete = (out_count == OUT_WORDS);

    // One shared sequential double-dabble converter formats both dimensions.
    // It runs during SD streaming, avoiding a combinational divider in the OSD.
    reg [27:0] bcd_shift;
    reg [4:0]  bcd_count;
    reg        bcd_busy;
    reg        bcd_height_phase;
    reg [11:0] bcd_pending_height;

    function [27:0] bcd_step;
        input [27:0] value;
        reg [27:0] work;
        begin
            work = value;
            if (work[27:24] >= 5) work[27:24] = work[27:24] + 3;
            if (work[23:20] >= 5) work[23:20] = work[23:20] + 3;
            if (work[19:16] >= 5) work[19:16] = work[19:16] + 3;
            if (work[15:12] >= 5) work[15:12] = work[15:12] + 3;
            bcd_step = {work[26:0], 1'b0};
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst || start || abort) begin
            byte_count         <= 0;
            data_offset        <= 32'd54;
            dib_size_low       <= 0;
            dib_size_large     <= 1'b0;
            source_width       <= 0;
            source_height      <= 0;
            width_large        <= 1'b0;
            height_large       <= 1'b0;
            planes_bad         <= 1'b0;
            bits_per_pixel_bad <= 1'b0;
            compression_bad    <= 1'b0;
            signature_bad      <= 1'b0;
            header_checked     <= 1'b0;
            format_bad         <= 1'b0;
            pixel_region       <= 1'b0;
            header_error       <= 1'b0;
            pad_count          <= 0;
            rgb_byte_count     <= 0;
            rgb_b              <= 0;
            rgb_g              <= 0;
            source_col         <= 0;
            source_row         <= 0;
            x_phase            <= 0;
            y_phase            <= 0;
            out_count          <= 0;
            bcd_shift          <= 0;
            bcd_count          <= 0;
            bcd_busy           <= 1'b0;
            bcd_height_phase   <= 1'b0;
            bcd_pending_height <= 0;
            src_width_bcd      <= 0;
            src_height_bcd     <= 0;
            dims_valid         <= 1'b0;
        end else begin
            header_error <= 1'b0;

            if (bcd_busy) begin
                if (bcd_count == 12) begin
                    if (!bcd_height_phase) begin
                        src_width_bcd    <= bcd_shift[27:12];
                        bcd_shift         <= {16'd0, bcd_pending_height};
                        bcd_count         <= 0;
                        bcd_height_phase  <= 1'b1;
                    end else begin
                        src_height_bcd <= bcd_shift[27:12];
                        bcd_busy        <= 1'b0;
                        dims_valid      <= 1'b1;
                    end
                end else begin
                    bcd_shift <= bcd_step(bcd_shift);
                    bcd_count <= bcd_count + 1'b1;
                end
            end

            if (byte_valid) begin
                byte_count <= byte_count + 1'b1;
                // Register the pixel-region boundary one byte early.  This
                // keeps the 32-bit offset comparison out of the scaler enables.
                if (header_checked && ((byte_count + 32'd1) == data_offset))
                    pixel_region <= 1'b1;

                if (!header_checked) begin
                    case (byte_count)
                        0:  signature_bad <= byte_in != 8'h42;
                        1:  signature_bad <= signature_bad || (byte_in != 8'h4d);
                        10, 11, 12, 13:
                            data_offset <= {byte_in, data_offset[31:8]};
                        14: dib_size_low <= byte_in;
                        15, 16, 17:
                            dib_size_large <= dib_size_large || (byte_in != 0);
                        18: source_width[7:0] <= byte_in;
                        19: begin
                            source_width[11:8] <= byte_in[3:0];
                            width_large <= width_large || (byte_in[7:4] != 0);
                        end
                        20, 21: width_large <= width_large || (byte_in != 0);
                        22: source_height[7:0] <= byte_in;
                        23: begin
                            source_height[11:8] <= byte_in[3:0];
                            height_large <= height_large || (byte_in[7:4] != 0);
                        end
                        24, 25: height_large <= height_large || (byte_in != 0);
                        26: planes_bad <= byte_in != 1;
                        27: planes_bad <= planes_bad || (byte_in != 0);
                        28: bits_per_pixel_bad <= byte_in != 24;
                        29: bits_per_pixel_bad <= bits_per_pixel_bad || (byte_in != 0);
                        30, 31, 32, 33:
                            compression_bad <= compression_bad || (byte_in != 0);
                        default: ;
                    endcase

                    // All fields through compression are stable by byte 34;
                    // data_offset>=54 guarantees this precedes pixel data.
                    if (byte_count == 34) begin
                        header_checked <= 1'b1;
                        if (signature_bad || (!dib_size_large && dib_size_low < 40) ||
                            planes_bad || bits_per_pixel_bad || compression_bad ||
                            width_large || height_large ||
                            (source_width < DST_W) || (source_width > 12'd2048) ||
                            (source_height < DST_H) || (source_height > 12'd2048) ||
                            offset_bad) begin
                            format_bad   <= 1'b1;
                            header_error <= 1'b1;
                        end else begin
                            x_phase <= source_width;
                            y_phase <= source_height;
                            bcd_shift          <= {16'd0, source_width};
                            bcd_pending_height <= source_height;
                            bcd_count          <= 0;
                            bcd_busy           <= 1'b1;
                            bcd_height_phase   <= 1'b0;
                        end
                    end
                end

                if (pixel_byte_valid) begin
                    if (pad_count != 0) begin
                        pad_count <= pad_count - 1'b1;
                    end else begin
                        case (rgb_byte_count)
                            0: begin
                                rgb_b <= byte_in;
                                rgb_byte_count <= 1;
                            end
                            1: begin
                                rgb_g <= byte_in;
                                rgb_byte_count <= 2;
                            end
                            2: begin
                                rgb_byte_count <= 0;
                                if (source_col == 0)
                                    x_phase <= source_width;
                                else if (x_selected)
                                    x_phase <= x_sum - {1'b0, DST_W};
                                else
                                    x_phase <= x_phase - DST_W;
                                if (pixel_valid)
                                    out_count <= out_count + 1'b1;

                                if (source_col == source_width - 1'b1) begin
                                    source_col <= 0;
                                    pad_count  <= source_width[1:0];
                                    source_row <= source_row + 1'b1;
                                    x_phase    <= source_width;
                                    if (source_row == 0)
                                        y_phase <= source_height;
                                    else if (y_selected)
                                        y_phase <= y_sum - {1'b0, DST_H};
                                    else
                                        y_phase <= y_phase - DST_H;
                                end else begin
                                    source_col <= source_col + 1'b1;
                                end
                            end
                            default: rgb_byte_count <= 0;
                        endcase
                    end
                end
            end
        end
    end
endmodule
