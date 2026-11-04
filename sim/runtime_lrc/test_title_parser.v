`timescale 1ns/1ps
module test_title_parser;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start_font=0,start_lrc=0,file_valid=0,file_done=0;
    reg [7:0] file_byte=0,file_error=0;
    reg [31:0] file_offset=0;
    wire font_ready,lyric_ready,parse_done,font_we,text_we,cue_we,title_we;
    wire [6:0] cue_count,cue_index;
    wire [11:0] font_addr;
    wire [15:0] font_data,cue_start;
    wire [10:0] text_addr,cue_base;
    wire [7:0] text_data,title_data;
    wire [4:0] cue_len,title_addr,title_count;
    integer i,j,phase=0,title_writes=0,text_writes=0,cue_writes=0;
    reg [7:0] seen_title[0:30];
    fat_lrc_loader dut(.start_timing(1'b0),.timing_clk(1'b0),.timing_read_addr(12'd0),.timing_read_data(),.timing_available(),.timing_ready(),.*);
    function [7:0] font_byte;
        input integer offset;
        begin
            font_byte=0;
            case(offset)
                0:font_byte="L";1:font_byte="F";2:font_byte="N";3:font_byte="T";
                4:font_byte=2;5:font_byte=202;
                10:font_byte="?";12:font_byte="A";
                408:font_byte=8'h60;409:font_byte=8'h4f; // glyph 200 = 你
                410:font_byte=8'h7d;411:font_byte=8'h59; // glyph 201 = 好
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if(title_we) begin
            if(title_addr>=31) $fatal(1,"title write beyond 31 chars");
            seen_title[title_addr]=title_data;title_writes=title_writes+1;
        end
        if(text_we) begin
            if(phase==1 && (text_addr!=text_writes || text_data!=(text_writes==0?2:200)))
                $fatal(1,"title consumed or corrupted lyric storage");
            text_writes=text_writes+1;
        end
        if(cue_we) begin
            if(cue_start!=123 || cue_base!=0 || cue_len!=2) $fatal(1,"lyric cue corrupted by metadata");
            cue_writes=cue_writes+1;
        end
    end
    task parse;
        input string content;
        begin
            title_writes=0;text_writes=0;cue_writes=0;
            @(negedge clk);start_lrc=1;
            @(negedge clk);start_lrc=0;
            if(title_count!=0) $fatal(1,"stale title after new file start");
            for(j=0;j<content.len();j=j+1) begin
                file_valid=1;file_offset=j;file_byte=content[j];@(negedge clk);
            end
            file_valid=0;file_done=1;@(negedge clk);file_done=0;
            wait(parse_done);@(negedge clk);
            if(!lyric_ready) $fatal(1,"valid LRC did not become ready");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        @(negedge clk);start_font=1;@(negedge clk);start_font=0;
        for(i=0;i<8712;i=i+1) begin
            file_valid=1;file_offset=i;file_byte=font_byte(i);@(negedge clk);
        end
        file_valid=0;file_done=1;@(negedge clk);file_done=0;
        wait(parse_done);@(negedge clk);
        if(!font_ready) $fatal(1,"font not ready");
        phase=1;
        parse("[ar:ignored]\n[ti:A你好~]\n[00:01.23]A你\n");
        if(title_count!=4 || title_writes!=4 || seen_title[0]!=2 || seen_title[1]!=200 ||
           seen_title[2]!=201 || seen_title[3]!=1 || cue_count!=1 || cue_writes!=1 || text_writes!=2)
            $fatal(1,"title decoding / fallback / lyrics mismatch");
        phase=2;
        parse("[ti:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA]\n");
        if(title_count!=31 || title_writes!=31 || cue_count!=0 || text_writes!=0)
            $fatal(1,"long title limit or title-only LRC mismatch");
        for(i=0;i<31;i=i+1) if(seen_title[i]!=2) $fatal(1,"long title glyph mismatch");
        phase=1;
        parse("[00:01.23]A你\n");
        if(title_count!=0 || title_writes!=0 || cue_count!=1 || text_writes!=2)
            $fatal(1,"old card no-title compatibility mismatch");
        phase=2;
        parse("[ti:]\n[tx:ignore]\n");
        if(title_count!=0 || title_writes!=0 || cue_count!=0) $fatal(1,"empty metadata mismatch");
        $display("PASS card LRC title parser, UTF-8, high glyph IDs, bounds and legacy lyrics");$finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
