`timescale 1ns/1ps
module test_resolution_osd;
    reg de=0,show=0,clean_mode=0;
    reg [9:0] pixel_x=0,pixel_y=0;
    reg [15:0] source_width_bcd=0,source_height_bcd=0;
    reg [23:0] base=24'h123456;
    wire [23:0] osd_rgb,clean_rgb;
    wire osd_active;
    integer errors=0;

    resolution_osd_overlay dut(
        .de(de),.pixel_x(pixel_x),.pixel_y(pixel_y),.show(show),
        .source_width_bcd(source_width_bcd),.source_height_bcd(source_height_bcd),
        .rgb_in(base),.rgb_out(osd_rgb),.osd_active(osd_active)
    );
    assign clean_rgb=clean_mode?base:osd_rgb;

    task at_pixel;
        input integer x,y;
        begin pixel_x=x;pixel_y=y;#1;end
    endtask
    task expect_rgb;
        input [23:0] expected;
        input [191:0] label;
        begin
            if(clean_rgb!==expected)begin
                $display("FAIL %0s at (%0d,%0d): got=%h expected=%h",
                    label,pixel_x,pixel_y,clean_rgb,expected);
                errors=errors+1;
            end
        end
    endtask

    initial begin
        de=1;show=1;source_width_bcd=16'h1200;source_height_bcd=16'h1200;
        at_pixel(492,30);expect_rgb(24'h101018,"background");
        if(!osd_active)begin $display("FAIL osd_active background");errors=errors+1;end
        at_pixel(498,32);expect_rgb(24'h44ddff,"leading 1");
        at_pixel(496,32);expect_rgb(24'h101018,"glyph gap");
        at_pixel(504,32);expect_rgb(24'h44ddff,"digit 2");
        at_pixel(631,41);expect_rgb(24'h101018,"right background");
        at_pixel(636,41);expect_rgb(base,"right outside");
        at_pixel(492,42);expect_rgb(base,"bottom outside");
        at_pixel(8,32);expect_rgb(base,"left OSD passthrough");

        source_width_bcd=16'h0640;source_height_bcd=16'h0480;
        at_pixel(498,32);expect_rgb(24'h101018,"native leading blank");
        at_pixel(504,32);expect_rgb(24'h44ddff,"native digit 6");
        at_pixel(544,32);expect_rgb(24'h44ddff,"native height 4 left");
        at_pixel(548,32);expect_rgb(24'h44ddff,"native height 4 right");

        source_width_bcd=16'h1100;source_height_bcd=16'h1200;
        at_pixel(506,32);expect_rgb(24'h44ddff,"1100 second 1");
        at_pixel(504,32);expect_rgb(24'h101018,"1100 glyph gap");

        show=0;at_pixel(498,32);expect_rgb(base,"hidden by browser/menu gate");
        show=1;de=0;at_pixel(498,32);expect_rgb(base,"blanking passthrough");
        de=1;clean_mode=1;at_pixel(498,32);expect_rgb(base,"clean bypass");
        clean_mode=0;at_pixel(498,32);expect_rgb(24'h44ddff,"clean restore");

        if(errors==0)begin $display("PASS test_resolution_osd");$finish;end
        else begin $display("FAIL test_resolution_osd errors=%0d",errors);$fatal(1);end
    end
endmodule
