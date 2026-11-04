`timescale 1ns/1ps

// Playback status consumes the same *consumed stereo-frame* count as LRC.
// One small restoring divider is shared by progress/time conversion during
// vertical blanking. No combinational division, multiplier or font BRAM.
module playback_status_overlay #(parameter integer INDEX_WIDTH=2) (
    input wire clk, rst_n, vsync, de,
    input wire [9:0] pixel_x, pixel_y,
    input wire [23:0] rgb_in,
    input wire [31:0] sample_count, total_frames,
    input wire [INDEX_WIDTH-1:0] song_index,
    input wire stream_active, wav_stream_end, paused, stopped,
    input wire [1:0] play_mode,
    output wire [23:0] rgb_out,
    output wire osd_active,
    input wire show_text,
    input wire [1:0] transition_active
);
    reg vs_q, stream_q, end_q, have_stream, ended;
    reg [INDEX_WIDTH-1:0] song_q;
    reg [31:0] kept_total;
    wire frame_start = vs_q && !vsync;
    reg [1:0] frame_pipe;
    // The image/song selector commits on frame_start too. Two clocks let
    // that commit and this module's song-change quarantine settle first.
    wire [31:0] effective_total = !have_stream ? 32'd0 :
        (total_frames != 0 ? total_frames : kept_total);
    wire [31:0] effective_count = !have_stream ? 32'd0 : ended ? effective_total :
        (effective_total != 0 && sample_count > effective_total ? effective_total : sample_count);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_q <= 1; stream_q <= 0; end_q <= 0; song_q <= 0;
            have_stream <= 0; ended <= 0; kept_total <= 0; frame_pipe <= 0;
        end else begin
            vs_q <= vsync; stream_q <= stream_active; end_q <= wav_stream_end;
            frame_pipe <= {frame_pipe[0],frame_start};
            song_q <= song_index;
            if (song_q != song_index) begin
                ended <= 0; kept_total <= 0;
                // The previous WAV may remain active briefly after a new
                // cover commits. Accept counts only after a fresh stream.
                have_stream <= stream_active && !stream_q;
            end else if (stream_active && !stream_q) begin
                ended <= 0; have_stream <= 1;
            end else if (wav_stream_end && !end_q && have_stream) ended <= 1;
            if (song_q == song_index && have_stream && total_frames != 0 && stream_active)
                kept_total <= total_frames;
        end
    end

    localparam S_IDLE=0, S_DIV=1, S_RESULT=2, S_HUNDREDS=3, S_TENS=4, S_COMMIT=5;
    reg [2:0] state, phase;
    reg [5:0] bits_left;
    reg [41:0] dividend;
    wire [41:0] quotient=dividend;
    reg [32:0] remainder;
    reg [31:0] divisor, frames_snapshot, count_snapshot;
    wire [32:0] shifted_rem = {remainder[31:0], dividend[41]};
    wire [33:0] rem_delta={1'b0,shifted_rem}-{2'b0,divisor};
    wire subtract_bit = !rem_delta[33];
    // A 32-bit source-frame position / 48000 never exceeds 89478 seconds.
    reg [16:0] elapsed_seconds, total_seconds;
    reg [9:0] progress_work, progress_pixels;
    reg [11:0] elapsed_min, total_min;
    reg [3:0] elapsed_hundreds, total_hundreds, elapsed_tens, total_tens;
    reg [5:0] elapsed_sec, total_sec;
    reg [19:0] elapsed_bcd, total_bcd;
    reg [INDEX_WIDTH-1:0] song_work,song_display;
    reg [1:0] mode_work,status_work,mode_display,status_display;

    function [3:0] tens60;
        input [5:0] value;
        begin
            if(value>=50) tens60=5;
            else if(value>=40) tens60=4;
            else if(value>=30) tens60=3;
            else if(value>=20) tens60=2;
            else if(value>=10) tens60=1;
            else tens60=0;
        end
    endfunction
    function [3:0] ones60;
        input [5:0] value;
        reg [3:0] tens;
        begin tens=tens60(value); ones60=value-((tens<<3)+(tens<<1)); end
    endfunction

    // 42 rounds for each divide, five divides per refresh. Results commit
    // together well before active row 48, so a frame never mixes old digits.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; phase<=0; bits_left<=0; dividend<=0;
            remainder<=0; divisor<=1; frames_snapshot<=0; count_snapshot<=0;
            elapsed_seconds<=0; total_seconds<=0; progress_work<=0; progress_pixels<=0;
            elapsed_min<=0; total_min<=0; elapsed_hundreds<=0; total_hundreds<=0;
            elapsed_tens<=0; total_tens<=0; elapsed_sec<=0; total_sec<=0;
            elapsed_bcd<=0; total_bcd<=0;
            song_work<=0; mode_work<=0; status_work<=3;
            song_display<=0; mode_display<=0; status_display<=3;
        end else case(state)
            S_IDLE: if(frame_pipe[1]) begin
                frames_snapshot<=effective_total; count_snapshot<=effective_count;
                song_work<=song_index; mode_work<=play_mode;
                status_work<=(stopped||ended)?2:!have_stream?3:paused?1:stream_active?0:3;
                // 608 = 512 + 64 + 32; widening before shifting preserves bits.
                dividend<=effective_total==0?42'd0:
                          ({10'd0,effective_count}<<9)+
                          ({10'd0,effective_count}<<6)+({10'd0,effective_count}<<5);
                divisor<=effective_total==0?32'd1:effective_total;
                remainder<=0; bits_left<=42; phase<=0; state<=S_DIV;
            end
            S_DIV: begin
                dividend<={dividend[40:0],subtract_bit};
                remainder<=subtract_bit?rem_delta[32:0]:shifted_rem;
                bits_left<=bits_left-1'b1;
                if(bits_left==1) state<=S_RESULT;
            end
            S_RESULT: begin
                remainder<=0; bits_left<=42; state<=S_DIV;
                case(phase)
                    0: begin
                        progress_work<=quotient>608?10'd608:quotient[9:0];
                        dividend<={10'd0,count_snapshot}; divisor<=48000; phase<=1;
                    end
                    1: begin
                        elapsed_seconds<=quotient[31:0];
                        dividend<={10'd0,frames_snapshot}; divisor<=48000; phase<=2;
                    end
                    2: begin
                        total_seconds<=quotient[31:0];
                        dividend<={10'd0,elapsed_seconds}; divisor<=60; phase<=3;
                    end
                    3: begin
                        elapsed_min<=quotient>999?12'd999:quotient[11:0];
                        elapsed_sec<=remainder[5:0];
                        dividend<={10'd0,total_seconds}; divisor<=60; phase<=4;
                    end
                    4: begin
                        total_min<=quotient>999?12'd999:quotient[11:0];
                        total_sec<=remainder[5:0];
                        elapsed_hundreds<=0; total_hundreds<=0;
                        elapsed_tens<=0; total_tens<=0; state<=S_HUNDREDS;
                    end
                    default: state<=S_IDLE;
                endcase
            end
            S_HUNDREDS: begin
                if(elapsed_min>=100) begin elapsed_min<=elapsed_min-100; elapsed_hundreds<=elapsed_hundreds+1'b1; end
                if(total_min>=100) begin total_min<=total_min-100; total_hundreds<=total_hundreds+1'b1; end
                if(elapsed_min<100 && total_min<100) state<=S_TENS;
            end
            S_TENS: begin
                if(elapsed_min>=10) begin elapsed_min<=elapsed_min-10; elapsed_tens<=elapsed_tens+1'b1; end
                if(total_min>=10) begin total_min<=total_min-10; total_tens<=total_tens+1'b1; end
                if(elapsed_min<10 && total_min<10) state<=S_COMMIT;
            end
            S_COMMIT: begin
                elapsed_bcd<={elapsed_hundreds,elapsed_tens,elapsed_min[3:0],tens60(elapsed_sec),ones60(elapsed_sec)};
                total_bcd<={total_hundreds,total_tens,total_min[3:0],tens60(total_sec),ones60(total_sec)};
                progress_pixels<=progress_work;
                song_display<=song_work; mode_display<=mode_work; status_display<=status_work;
                state<=S_IDLE;
            end
            default: state<=S_IDLE;
        endcase
    end

    // A compact 5x7 font is implemented as logic; one row selected per pixel.
    function [34:0] glyph;
        input [7:0] c;
        begin case(c)
            "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
            "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
            "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
            "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
            "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
            "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
            "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
            "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
            "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
            "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
            "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
            "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
            "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
            "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
            "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
            "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
            "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
            "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
            "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
            "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
            "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
            "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
            "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
            "Q":glyph=35'b01110_10001_10001_10001_10101_10010_01101;
            "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
            "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
            "W":glyph=35'b10001_10001_10001_10101_10101_10101_01010;
            "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
            ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
            "/":glyph=35'b00001_00001_00010_00100_01000_10000_10000;
            default:glyph=0;
        endcase end
    endfunction
    reg [7:0] character;
    wire [9:0] rel_x = pixel_x-10'd8;
    wire [5:0] char_index = rel_x[8:3];
    reg [34:0] glyph_bits;
    reg [4:0] row_bits;
    reg text_hit;
    always @* begin
        character=" ";
        case(char_index)
            0:character="S"; 1:character="O"; 2:character="N"; 3:character="G";
            4:character=(song_display>=9)?"1":" ";
            5:character=(song_display>=9)?"0"+(song_display-9):"1"+song_display;
            7:character="0"+elapsed_bcd[19:16];
            8:character="0"+elapsed_bcd[15:12];
            9:character="0"+elapsed_bcd[11:8];
            10:character=":";
            11:character="0"+elapsed_bcd[7:4];
            12:character="0"+elapsed_bcd[3:0];
            13:character="/";
            14:character="0"+total_bcd[19:16];
            15:character="0"+total_bcd[15:12];
            16:character="0"+total_bcd[11:8];
            17:character=":";
            18:character="0"+total_bcd[7:4];
            19:character="0"+total_bcd[3:0];
            21:character=status_display==2?"S":status_display==3?"L":"P";
            22:character=status_display==0?"L":status_display==1?"A":status_display==2?"T":"O";
            23:character=status_display==0?"A":status_display==1?"U":status_display==2?"O":"A";
            24:character=status_display==0?"Y":status_display==1?"S":status_display==2?"P":"D";
            25:character=status_display==1?"E":" ";
            26:character=mode_display==0?"L":mode_display==1?"S":"R";
            27:character=mode_display==0?"O":mode_display==1?"E":"N";
            28:character=mode_display==0?"O":mode_display==1?"Q":"D";
            29:character=mode_display==0?"P":" ";
            31:character=transition_active==1?"F":transition_active==2?"W":" ";
            32:character=transition_active==1?"A":transition_active==2?"I":" ";
            33:character=transition_active==1?"D":transition_active==2?"P":" ";
            34:character=transition_active==0?" ":"E";
            default:character=" ";
        endcase
        glyph_bits=glyph(character);
        case(pixel_y[2:0])
            0:row_bits=glyph_bits[34:30]; 1:row_bits=glyph_bits[29:25];
            2:row_bits=glyph_bits[24:20]; 3:row_bits=glyph_bits[19:15];
            4:row_bits=glyph_bits[14:10]; 5:row_bits=glyph_bits[9:5];
            6:row_bits=glyph_bits[4:0]; default:row_bits=0;
        endcase
        text_hit=rel_x[2:0]<5 && row_bits[4-rel_x[2:0]];
    end
    wire in_text=de && pixel_y>=48 && pixel_y<56 && pixel_x>=8 && pixel_x<288;
    wire in_bar=de && pixel_y>=468 && pixel_y<476 && pixel_x>=16 && pixel_x<624;
    wire border=(pixel_y==468 || pixel_y==475 || pixel_x==16 || pixel_x==623);
    wire filled=(pixel_x-10'd16)<progress_pixels;
    wire [23:0] accent=status_display==1?24'hffdd33:status_display==2?24'hff8844:24'h44ddff;
    assign osd_active=(in_text&&show_text)||in_bar;
    assign rgb_out=(in_text&&show_text)?(text_hit?accent:24'h101018):
                   in_bar?(border?24'ha0a0a0:filled?accent:24'h202028):rgb_in;
endmodule
