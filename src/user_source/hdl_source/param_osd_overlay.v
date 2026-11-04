`timescale 1ns/1ps

// 第14课(课件第13课)：亮度/对比度参数OSD（第二状态行）
// 在(8,20)渲染 "Bxxx Cxxx"（8字符x8px=64px宽，5x7字库，BCD直接查数字字形），
// 结构仿osd_overlay_24：组合叠加零延迟，line_y由vsync/de重建，参数帧边界锁存。
// 独立新模块而非改status_osd_overlay——不动第9课已验证文件。
module param_osd_overlay #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 20
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire [11:0] bright_bcd,   // {百位,十位,个位}，帧边界锁存后的值
    input  wire [11:0] contr_bcd,
    input wire paused,stopped,
    input wire [1:0] play_mode,
    input wire [4:0] volume,
    input wire volume_mode,
    input wire [2:0] bass,mid,treble,edit_target,
    input wire clipped,
    output wire [23:0] rgb_out,
    output wire        osd_active
);
    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    wire frame_start = vs_q && !vsync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q   <= 1'b0;
            vs_q   <= 1'b1;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;
        end
    end

    // 参数帧边界锁存（一帧内不变，不撕裂）
    reg [11:0] bright_q;
    reg [11:0] contr_q;
    reg [1:0] state_q,mode_q;
    reg [4:0] volume_q;
    reg volume_mode_q;
    reg [2:0] bass_q,mid_q,treble_q,edit_q;
    reg clipped_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bright_q <= 12'h255;
            contr_q  <= 12'h128;
            state_q<=0;mode_q<=0;volume_q<=16;volume_mode_q<=0;
            bass_q<=2;mid_q<=2;treble_q<=2;edit_q<=0;clipped_q<=0;
        end else if (frame_start) begin
            bright_q <= bright_bcd;
            contr_q  <= contr_bcd;
            state_q<=stopped?2:paused?1:0;mode_q<=play_mode;volume_q<=volume;
            volume_mode_q<=volume_mode;
            bass_q<=bass;mid_q<=mid;treble_q<=treble;edit_q<=edit_target;clipped_q<=clipped;
        end
    end

    // 5x7字库：数字0-9（同status_osd_overlay）+ B/C
    function [4:0] font_row;
        input [4:0] value;
        input [2:0] row;
        begin
            case (value)
                4'h0: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b10001;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                4'h1: case(row) 0:font_row=5'b00100;1:font_row=5'b01100;2:font_row=5'b00100;3:font_row=5'b00100;4:font_row=5'b00100;5:font_row=5'b00100;default:font_row=5'b11111; endcase
                4'h2: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b11111; endcase
                4'h3: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                4'h4: case(row) 0:font_row=5'b10001;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b00001; endcase
                4'h5: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                4'h6: case(row) 0:font_row=5'b11111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                4'h7: case(row) 0:font_row=5'b11111;1:font_row=5'b00001;2:font_row=5'b00010;3:font_row=5'b00100;4:font_row=5'b01000;5:font_row=5'b01000;default:font_row=5'b01000; endcase
                4'h8: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11111; endcase
                4'h9: case(row) 0:font_row=5'b11111;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11111;4:font_row=5'b00001;5:font_row=5'b00001;default:font_row=5'b11111; endcase
                4'hb: case(row) 0:font_row=5'b11110;1:font_row=5'b10001;2:font_row=5'b10001;3:font_row=5'b11110;4:font_row=5'b10001;5:font_row=5'b10001;default:font_row=5'b11110; endcase
                4'hc: case(row) 0:font_row=5'b01111;1:font_row=5'b10000;2:font_row=5'b10000;3:font_row=5'b10000;4:font_row=5'b10000;5:font_row=5'b10000;default:font_row=5'b01111; endcase
                4'ha: case(row) 0:font_row=5'b11110;1,2:font_row=5'b10001;3:font_row=5'b11110;default:font_row=5'b10000;endcase
                4'hd: case(row) 0,1,2,3,4:font_row=5'b10001;5:font_row=5'b01010;default:font_row=5'b00100;endcase
                4'he: case(row) 0:font_row=5'b10001;1:font_row=5'b11011;2:font_row=5'b10101;default:font_row=5'b10001;endcase
                5'h10:case(row) 6:font_row=5'b11111;default:font_row=5'b10000;endcase // L
                5'h11:case(row) 3:font_row=5'b11111;default:font_row=5'b10001;endcase // H
                5'h12:case(row) 1,2,4,5:font_row=5'b00100;3:font_row=5'b11111;default:font_row=0;endcase // +
                5'h13:case(row) 3:font_row=5'b11111;default:font_row=0;endcase // -
                5'h14:case(row) 0,6:font_row=5'b11111;default:font_row=5'b00100;endcase // I
                5'h15:case(row) 0,3,6:font_row=5'b11111;1,2:font_row=5'b10000;default:font_row=5'b00001;endcase // S
                5'h16:case(row) 0,3,6:font_row=5'b11111;default:font_row=5'b10000;endcase // E
                5'h17:case(row) 0,6:font_row=5'b10001;1,5:font_row=5'b10010;2,4:font_row=5'b10100;default:font_row=5'b11000;endcase // K
                default: font_row = 5'b00000;
            endcase
        end
    endfunction

    // "Bxxx Cxxx"：字符0=B、1-3=亮度BCD、字符4=C、5-7=对比度BCD（8字符x8px=64px）
    reg        osd_hit;
    reg [4:0]  char_value;
    reg [2:0]  char_row;
    reg [4:0]  glyph_row;
    reg [23:0] osd_color;
    reg [4:0] eq_pos;
    reg [2:0] eq_level;
    function [4:0] gain_digit;
      input [2:0] level;
      begin case(level) 0,4:gain_digit=6;1,3:gain_digit=3;default:gain_digit=0;endcase end
    endfunction
    always @* begin
        osd_hit    = 1'b0;
        char_value = 4'h0;
        char_row   = line_y[2:0] - OSD_Y[2:0];
        glyph_row  = 5'b00000;
        osd_color=24'h44DDFF;eq_pos=0;eq_level=2;
        if (pixel_x >= OSD_X && pixel_x < OSD_X + 144 &&
            line_y >= OSD_Y && line_y < OSD_Y + 8) begin
            case ((pixel_x - OSD_X) / 8)
                0: char_value = 4'hb;
                1: char_value = bright_q[11:8];
                2: char_value = bright_q[7:4];
                3: char_value = bright_q[3:0];
                4: char_value = 4'hc;
                5: char_value = contr_q[11:8];
                6: char_value = contr_q[7:4];
                7: char_value = contr_q[3:0];
                8: char_value=4'hf;
                9: char_value=4'ha;
                10:char_value={2'b0,state_q};
                11:char_value=4'hf;
                12:char_value=4'hd;
                13:char_value=volume_q>=10?1:0;
                14:char_value=volume_q>=10?volume_q-10:volume_q;
                15:char_value=4'hf;
                16:char_value=4'he;
                17:char_value={2'b0,mode_q}+1'b1;
                default: char_value = 4'hf;
            endcase
            char_row  = line_y - OSD_Y;
            glyph_row = font_row(char_value, char_row);
            if ((pixel_x - OSD_X) % 8 < 5 && char_row < 7)
                osd_hit = glyph_row[4 - ((pixel_x - OSD_X) % 8)];
            if(volume_mode_q && pixel_x>=OSD_X+96 && pixel_x<OSD_X+120) osd_color=24'hFFFF00;
        end else if(pixel_x>=OSD_X && pixel_x<OSD_X+152 &&
                    line_y>=OSD_Y+12 && line_y<OSD_Y+20) begin
            // Third row: L+00 M+00 H+00 [CLIP]. Values are requested dB.
            eq_pos=(pixel_x-OSD_X)/8;
            if(eq_pos<4)eq_level=bass_q;else if(eq_pos<9)eq_level=mid_q;else eq_level=treble_q;
            char_value=5'hf;
            case(eq_pos)
             0:char_value=5'h10;5:char_value=5'he;10:char_value=5'h11;
             1,6,11:char_value=eq_level<2?5'h13:5'h12;
             2,7,12:char_value=0;
             3,8,13:char_value=gain_digit(eq_level);
             15:if(clipped_q)char_value=5'hc;
             16:if(clipped_q)char_value=5'h10;
             17:if(clipped_q)char_value=5'h14;
             18:if(clipped_q)char_value=5'ha;
             default:;
            endcase
            if(edit_q==5)begin
                char_value=5'hf;osd_color=24'hffff00;
                case(eq_pos)
                 0:char_value=5'h15;1,2:char_value=5'h16;3:char_value=5'h17;
                 5:char_value=5'h13;6,10:char_value=1;7,11:char_value=0;9:char_value=5'h12;
                 default:;
                endcase
            end
            char_row=line_y-OSD_Y-12;
            glyph_row=font_row(char_value,char_row);
            if((pixel_x-OSD_X)%8<5 && char_row<7)
                osd_hit=glyph_row[4-((pixel_x-OSD_X)%8)];
            if((edit_q==2&&eq_pos<4)||(edit_q==3&&eq_pos>=5&&eq_pos<9)||
               (edit_q==4&&eq_pos>=10&&eq_pos<14)) osd_color=24'hFFFF00;
            if(eq_pos>=15)osd_color=24'hFF4444;
        end
    end

    // 参数行用淡蓝色12'h4df（与状态行黄/红区分），4bit/通道复制成8bit
    assign rgb_out = (de && osd_hit) ? osd_color : rgb_in;
    assign osd_active = osd_hit && de;
endmodule
