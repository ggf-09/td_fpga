`timescale 1ns/1ps
// Full-screen source-resolution label.  Dimensions come from the loaded BMP
// header, not from a filename or a fixed demonstration string.
module resolution_osd_overlay (
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        show,
    input  wire [15:0] source_width_bcd,
    input  wire [15:0] source_height_bcd,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output wire        osd_active
);
    localparam [4:0] CHAR_X = 5'd10;
    localparam [4:0] CHAR_ARROW = 5'd11;
    localparam [4:0] CHAR_BLANK = 5'd15;

    function [4:0] font_row;
        input [4:0] character;
        input [2:0] row;
        begin
            case (character)
                0: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b10001;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111;endcase
                1: case(row) 0:font_row=5'b00100;1:font_row=5'b01100;2:font_row=5'b00100;3:font_row=5'b00100;4:font_row=5'b00100;5:font_row=5'b00100;default:font_row=5'b11111;endcase
                2: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111;endcase
                3: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111;endcase
                4: case(row) 0:font_row=5'b10001;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b00001;endcase
                5: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111;endcase
                6: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111;endcase
                7: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00010;3:font_row=5'b00100;4:font_row=5'b01000;5:font_row=5'b01000;default:font_row=5'b01000;endcase
                8: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111;endcase
                9: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111;endcase
                CHAR_X: case(row) 0,1,5:font_row=5'b10001;2,4:font_row=5'b01010;3:font_row=5'b00100;default:font_row=5'b10001;endcase
                CHAR_ARROW: case(row) 0,6:font_row=5'b10000;1,5:font_row=5'b01000;2,4:font_row=5'b00100;default:font_row=5'b00010;endcase
                default: font_row = 5'b00000;
            endcase
        end
    endfunction

    function [4:0] leading_digit;
        input [3:0] digit;
        input       suppress;
        begin
            leading_digit = (suppress && digit == 0) ? CHAR_BLANK : {1'b0, digit};
        end
    endfunction

    wire in_text = de && show && pixel_x >= 496 && pixel_x < 632 &&
                   pixel_y >= 32 && pixel_y < 40;
    wire in_background = de && show && pixel_x >= 492 && pixel_x < 636 &&
                         pixel_y >= 30 && pixel_y < 42;
    wire [9:0] rel_x = pixel_x - 10'd496; // valid only in_text
    wire [4:0] char_index = rel_x[7:3];
    wire [2:0] char_row = pixel_y[2:0];

    reg [4:0] character;
    always @* begin
        case (char_index)
            0: character = leading_digit(source_width_bcd[15:12], 1'b1);
            1: character = leading_digit(source_width_bcd[11:8], source_width_bcd[15:12] == 0);
            2: character = leading_digit(source_width_bcd[7:4], source_width_bcd[15:8] == 0);
            3: character = {1'b0, source_width_bcd[3:0]};
            4: character = CHAR_X;
            5: character = leading_digit(source_height_bcd[15:12], 1'b1);
            6: character = leading_digit(source_height_bcd[11:8], source_height_bcd[15:12] == 0);
            7: character = leading_digit(source_height_bcd[7:4], source_height_bcd[15:8] == 0);
            8: character = {1'b0, source_height_bcd[3:0]};
            9: character = CHAR_ARROW;
            10: character = 6;
            11: character = 4;
            12: character = 0;
            13: character = CHAR_X;
            14: character = 4;
            15: character = 8;
            16: character = 0;
            default: character = CHAR_BLANK;
        endcase
    end

    wire [4:0] glyph = font_row(character, char_row);
    wire text_hit = in_text && (rel_x[2:0] < 5) && (pixel_y < 39) &&
                    glyph[3'd4 - rel_x[2:0]];
    assign rgb_out = in_background ? (text_hit ? 24'h44DDFF : 24'h101018) : rgb_in;
    assign osd_active = in_background;
endmodule
