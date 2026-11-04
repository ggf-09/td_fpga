`timescale 1ns/1ps
module test_pic_decoder;
    reg clk=0,rst=1,start=0,abort=0,byte_valid=0;
    reg [31:0] file_size=0;
    reg [7:0] byte_in=0;
    wire pixel_valid,scale_complete,header_error,dims_valid;
    wire [23:0] pixel_rgb;
    wire [18:0] out_count;
    wire [15:0] src_width_bcd,src_height_bcd;
    integer errors=0,emit_count=0,header_error_seen=0;
    integer current_w=640,current_h=480;
    integer ref_ox,ref_oy,ref_sx,ref_sy;
    reg expect_header_ok=1;

    always #5 clk=~clk;
    bmp_pic_decoder dut(
        .clk(clk),.rst(rst),.start(start),.abort(abort),.file_size(file_size),
        .byte_valid(byte_valid),.byte_in(byte_in),.pixel_valid(pixel_valid),
        .pixel_rgb(pixel_rgb),.out_count(out_count),.scale_complete(scale_complete),
        .header_error(header_error),.src_width_bcd(src_width_bcd),
        .src_height_bcd(src_height_bcd),.dims_valid(dims_valid)
    );

    function [23:0] pattern;
        input integer row,col;
        reg [7:0] pr,pg,pb;
        begin
            pr=(row*3+col*5)&255;
            pg=(row*7+col*11)&255;
            pb=(row*13+col*17)&255;
            pattern={pr,pg,pb};
        end
    endfunction
    function [15:0] bcd;
        input integer value;
        begin
            bcd=((value/1000)%10)*4096+((value/100)%10)*256+
                ((value/10)%10)*16+(value%10);
        end
    endfunction

    // Independent reference: ordinary integer division, not the DUT accumulator.
    always @(posedge clk) begin
        if(header_error) begin
            header_error_seen=header_error_seen+1;
            if(expect_header_ok) begin
                $display("FAIL unexpected header error");errors=errors+1;
            end
        end
        if(pixel_valid) begin
            if(emit_count>=307200) begin
                $display("FAIL excess output pixel");errors=errors+1;
            end else begin
                ref_ox=emit_count%640;ref_oy=emit_count/640;
                ref_sx=(ref_ox*current_w)/640;ref_sy=(ref_oy*current_h)/480;
                if(pixel_rgb!==pattern(ref_sy,ref_sx)) begin
                    if(errors<12)$display("FAIL pixel %0d src(%0d,%0d) got=%h expected=%h",
                        emit_count,ref_sy,ref_sx,pixel_rgb,pattern(ref_sy,ref_sx));
                    errors=errors+1;
                end
            end
            emit_count=emit_count+1;
        end
    end

    task send_byte;
        input [7:0] value;
        begin
            @(negedge clk);byte_in=value;byte_valid=1;
        end
    endtask
    task send16;
        input [15:0] value;
        begin send_byte(value[7:0]);send_byte(value[15:8]);end
    endtask
    task send32;
        input [31:0] value;
        begin send_byte(value[7:0]);send_byte(value[15:8]);send_byte(value[23:16]);send_byte(value[31:24]);end
    endtask
    task pulse_start;
        begin
            @(negedge clk);start=1;byte_valid=0;
            @(negedge clk);start=0;
        end
    endtask
    task send_header;
        input integer w,h,offset,bpp,compression,planes;
        input top_down;
        begin
            send_byte(8'h42);send_byte(8'h4d);send32(file_size);send32(0);
            send32(offset);send32(40);send32(w);send32(top_down?-h:h);
            send16(planes);send16(bpp);send32(compression);send32(0);
            send32(0);send32(0);send32(0);send32(0);
        end
    endtask
    task check_equal;
        input integer actual,expected;
        input [127:0] label;
        begin
            if(actual!==expected)begin
                $display("FAIL %0s actual=%0d expected=%0d",label,actual,expected);
                errors=errors+1;
            end
        end
    endtask

    task run_case;
        input integer case_id,w,h,offset,bpp,compression,planes;
        input top_down,expect_ok;
        integer row,col,pad,stride;
        begin
            $display("RUN case %0d %0dx%0d offset=%0d expect_ok=%0d",case_id,w,h,offset,expect_ok);
            current_w=w;current_h=h;expect_header_ok=expect_ok;
            emit_count=0;header_error_seen=0;
            stride=((w*3+3)/4)*4;pad=w%4;
            file_size=offset+stride*h;
            pulse_start();
            send_header(w,h,offset,bpp,compression,planes,top_down);
            for(row=54;row<offset;row=row+1)send_byte(8'ha5);
            if(expect_ok)begin
                for(row=0;row<h;row=row+1)begin
                    for(col=0;col<w;col=col+1)begin
                        send_byte(pattern(row,col)&255);
                        send_byte((pattern(row,col)>>8)&255);
                        send_byte((pattern(row,col)>>16)&255);
                    end
                    for(col=0;col<pad;col=col+1)send_byte(8'hde+col);
                end
            end
            @(negedge clk);byte_valid=0;byte_in=0;
            repeat(35)@(posedge clk);
            #1;
            check_equal(header_error_seen,expect_ok?0:1,"header error count");
            check_equal(emit_count,expect_ok?307200:0,"emitted pixels");
            check_equal(out_count,expect_ok?307200:0,"DUT output count");
            check_equal(scale_complete,expect_ok?1:0,"scale complete");
            check_equal(dims_valid,expect_ok?1:0,"dimensions valid");
            if(expect_ok)begin
                if(src_width_bcd!==bcd(w))begin
                    $display("FAIL width BCD=%h expected=%h",src_width_bcd,bcd(w));errors=errors+1;
                end
                if(src_height_bcd!==bcd(h))begin
                    $display("FAIL height BCD=%h expected=%h",src_height_bcd,bcd(h));errors=errors+1;
                end
            end
        end
    endtask

    initial begin
        repeat(4)@(negedge clk);rst=0;
        run_case(1,640,480,54,24,0,1,0,1);
        run_case(2,1280,960,54,24,0,1,0,1);
        run_case(3,1920,1080,54,24,0,1,0,1);
        run_case(4,1200,1200,70,24,0,1,0,1);
        run_case(5,1100,1200,54,24,0,1,0,1);
        run_case(6,641,481,54,24,0,1,0,1);
        run_case(7,642,482,54,24,0,1,0,1);
        run_case(8,643,483,54,24,0,1,0,1);
        run_case(9,640,480,54,24,0,1,1,0);
        run_case(10,640,480,54,32,0,1,0,0);
        run_case(11,640,480,54,24,1,1,0,0);
        run_case(12,639,480,54,24,0,1,0,0);
        run_case(13,640,479,54,24,0,1,0,0);
        run_case(14,2049,2048,54,24,0,1,0,0);
        run_case(15,640,480,40,24,0,1,0,0);
        if(errors==0)begin $display("PASS test_pic_decoder");$finish;end
        else begin $display("FAIL test_pic_decoder errors=%0d",errors);$fatal(1);end
    end
endmodule
