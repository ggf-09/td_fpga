`timescale 1ns/1ps

// Canonical 44-byte RIFF/WAVE, PCM signed 16-bit stereo, 48 kHz.
// The FAT streamer supplies bytes and can be paused between sectors. This
// module reserves a complete sector of FIFO space before allowing the next
// request, so no audio frame is lost while a sector is being transferred.
module fat_wav_player #(
    parameter integer ADDR_WIDTH = 12
) (
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        file_valid,
    input  wire [7:0]  file_byte,
    input  wire [31:0] file_byte_offset,
    input  wire        file_done,
    input  wire [7:0]  file_error,
    output wire        can_read_sector,
    output reg         format_error,
    output wire        stream_end,
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,
    input  wire        paused,
    input  wire        sample_ready,
    output reg         sample_valid,
    output reg signed [15:0] sample_left,
    output reg signed [15:0] sample_right,
    output reg [31:0]  sample_counter,
    output reg [31:0]  underflow_count
);
    localparam integer DEPTH = (1 << ADDR_WIDTH);
    reg [31:0] fifo [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;
    reg [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2;
    reg [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_seen;
    reg [7:0] b0, b1, b2;
    reg file_complete;
    reg complete_sync1, complete_sync2;
    reg [31:0] fifo_data;

    function [ADDR_WIDTH:0] gray;
        input [ADDR_WIDTH:0] value;
        begin gray = (value >> 1) ^ value; end
    endfunction

    function [ADDR_WIDTH:0] ungray;
        input [ADDR_WIDTH:0] value;
        integer bitno;
        begin
            ungray[ADDR_WIDTH] = value[ADDR_WIDTH];
            for (bitno = ADDR_WIDTH-1; bitno >= 0; bitno = bitno-1)
                ungray[bitno] = ungray[bitno+1] ^ value[bitno];
        end
    endfunction

    wire [ADDR_WIDTH:0] wr_seen = ungray(wr_gray_sync2);
    wire [ADDR_WIDTH:0] fill_wr = wr_ptr - rd_seen;
    wire empty_rd = (rd_ptr == wr_seen);
    wire full_wr = (fill_wr == DEPTH);
    wire header_phase = (file_byte_offset[31:6] == 0) &&
                        (file_byte_offset[5:0] < 6'd44);
    assign can_read_sector = (fill_wr <= DEPTH-128);
    assign stream_end = complete_sync2 && empty_rd;

    // The 44-byte header is checked byte by byte. Files with extra RIFF
    // chunks are rejected; the PC-side preparation tool writes this layout.
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr <= 0;
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
            rd_seen <= 0;
            b0 <= 0;
            b1 <= 0;
            b2 <= 0;
            format_error <= 1'b0;
            file_complete <= 1'b0;
        end else begin
            rd_gray_sync1 <= gray(rd_ptr);
            rd_gray_sync2 <= rd_gray_sync1;
            // Break the Gray decode/subtract/write-enable timing path. The
            // sector gate reserves 128 words, so one extra sync cycle is safe.
            rd_seen <= ungray(rd_gray_sync2);
            if (file_done) begin
                file_complete <= 1'b1;
                if (file_error != 0) format_error <= 1'b1;
            end
            if (file_valid) begin
                if (header_phase) case (file_byte_offset[5:0])
                    0:  if (file_byte != "R") format_error <= 1'b1;
                    1:  if (file_byte != "I") format_error <= 1'b1;
                    2:  if (file_byte != "F") format_error <= 1'b1;
                    3:  if (file_byte != "F") format_error <= 1'b1;
                    8:  if (file_byte != "W") format_error <= 1'b1;
                    9:  if (file_byte != "A") format_error <= 1'b1;
                    10: if (file_byte != "V") format_error <= 1'b1;
                    11: if (file_byte != "E") format_error <= 1'b1;
                    12: if (file_byte != "f") format_error <= 1'b1;
                    13: if (file_byte != "m") format_error <= 1'b1;
                    14: if (file_byte != "t") format_error <= 1'b1;
                    15: if (file_byte != " ") format_error <= 1'b1;
                    16: if (file_byte != 8'd16) format_error <= 1'b1;
                    17,18,19: if (file_byte != 0) format_error <= 1'b1;
                    20: if (file_byte != 8'd1) format_error <= 1'b1;
                    21: if (file_byte != 0) format_error <= 1'b1;
                    22: if (file_byte != 8'd2) format_error <= 1'b1;
                    23: if (file_byte != 0) format_error <= 1'b1;
                    24: if (file_byte != 8'h80) format_error <= 1'b1;
                    25: if (file_byte != 8'hbb) format_error <= 1'b1;
                    26,27: if (file_byte != 0) format_error <= 1'b1;
                    28: if (file_byte != 8'h00) format_error <= 1'b1;
                    29: if (file_byte != 8'hee) format_error <= 1'b1;
                    30: if (file_byte != 8'h02) format_error <= 1'b1;
                    31: if (file_byte != 0) format_error <= 1'b1;
                    32: if (file_byte != 8'd4) format_error <= 1'b1;
                    33: if (file_byte != 0) format_error <= 1'b1;
                    34: if (file_byte != 8'd16) format_error <= 1'b1;
                    35: if (file_byte != 0) format_error <= 1'b1;
                    36: if (file_byte != "d") format_error <= 1'b1;
                    37: if (file_byte != "a") format_error <= 1'b1;
                    38: if (file_byte != "t") format_error <= 1'b1;
                    39: if (file_byte != "a") format_error <= 1'b1;
                    default: ;
                endcase
                if (!header_phase && !format_error) begin
                    case (file_byte_offset[1:0])
                        2'd0: b0 <= file_byte;
                        2'd1: b1 <= file_byte;
                        2'd2: b2 <= file_byte;
                        2'd3: begin
                            if (!full_wr) begin
                                fifo[wr_ptr[ADDR_WIDTH-1:0]] <= {file_byte,b2,b1,b0};
                                wr_ptr <= wr_ptr + 1'b1;
                            end else format_error <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

    always @(posedge rd_clk) begin
        fifo_data <= fifo[rd_ptr[ADDR_WIDTH-1:0]];
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr <= 0;
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
            complete_sync1 <= 0;
            complete_sync2 <= 0;
            sample_valid <= 0;
            sample_left <= 0;
            sample_right <= 0;
            sample_counter <= 0;
            underflow_count <= 0;
        end else begin
            wr_gray_sync1 <= gray(wr_ptr);
            wr_gray_sync2 <= wr_gray_sync1;
            complete_sync1 <= file_complete;
            complete_sync2 <= complete_sync1;
            sample_valid <= 1'b0;
            if (sample_tick && sample_ready) begin
                sample_valid <= 1'b1;
                if (paused) begin
                    sample_left <= 0;
                    sample_right <= 0;
                end else if (!empty_rd) begin
                    sample_left <= fifo_data[15:0];
                    sample_right <= fifo_data[31:16];
                    rd_ptr <= rd_ptr + 1'b1;
                    sample_counter <= sample_counter + 1'b1;
                end else begin
                    sample_left <= 0;
                    sample_right <= 0;
                    if (!complete_sync2)
                        underflow_count <= underflow_count + 1'b1;
                end
            end
        end
    end
endmodule

// Sequential division is also valid when source position jumps backwards.
module audio_position_clock(
 input wire clk,rst_n,input wire [31:0] sample_position,
 output reg [15:0] centiseconds
);
 // floor(position/480) == floor((position >> 5)/15).
 // Factoring the power of two removes five divider bits without precision loss.
 reg [26:0] shift;
 reg [3:0] remainder;
 reg [4:0] rounds;
 wire [4:0] trial={remainder,shift[26]};
 wire subtract=trial>=15;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin shift<=0;remainder<=0;rounds<=0;centiseconds<=0;end
  else if(rounds==0)begin shift<=sample_position[31:5];remainder<=0;rounds<=27;end
  else begin
   shift<={shift[25:0],subtract};
   remainder<=subtract?trial-15:trial;
   rounds<=rounds-1'b1;
   if(rounds==1)centiseconds<=shift[25:15]!=0?16'hffff:{shift[14:0],subtract};
  end
 end
endmodule
