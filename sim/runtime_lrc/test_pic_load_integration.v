`timescale 1ns/1ps
module test_pic_load_integration;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,sd_init_done=0,cache_invalidate=0,scan_done_latched=0;
    reg [3:0] scan_valid_latched=1;reg scanner_menu_valid=0;
    reg [31:0] scanner_menu_cluster=901,scanner_menu_size=921654;
    wire loader_load_done;wire [7:0] loader_memory_error;
    reg streamer_file_done=0;reg [7:0] streamer_fs_error=0;
    wire decoder_scale_complete,decoder_header_error,decoder_dims_valid;
    wire [15:0] decoder_width_bcd,decoder_height_bcd;
    wire menu_ready,load_menu,load_start,load_abort,frame_commit,sd_free;
    wire [7:0] decode_error;wire [1:0] load_image_index;
    wire [31:0] load_cluster,load_file_size;
    wire pixel_valid;wire [23:0] pixel_rgb;wire [18:0] out_count;
    reg byte_valid=0;reg [7:0] byte_in=0;
    reg [1:0] requested_slot=0;
    wire streamer_byte_valid=byte_valid;
    wire loader_busy,we;wire [3:0] complete,mask;
    wire [20:0] addr;wire [31:0] data;
    integer written=0,done_count=0,errors=0,current_w=640,current_h=480;
    integer ref_ox,ref_oy,ref_sx,ref_sy,expected_addr;
    reg check_writes=0;

    menu_boot_fragment boot(.*);
    bmp_pic_decoder decoder(
        .clk(clk),.rst(rst),.start(load_start),.abort(load_abort|cache_invalidate),
        .file_size(load_file_size),.byte_valid(byte_valid),.byte_in(byte_in),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.out_count(out_count),
        .scale_complete(decoder_scale_complete),.header_error(decoder_header_error),
        .src_width_bcd(decoder_width_bcd),.src_height_bcd(decoder_height_bcd),
        .dims_valid(decoder_dims_valid)
    );
    media_frame_loader loader(
        .clk(clk),.rst_n(!rst),.load_start(load_start),
        .menu_load(load_menu),.image_index(load_image_index),
        // 软失效语义与顶层一致：invalidate清完成位（本测试不带keep=全清）
        .cache_invalidate(cache_invalidate),.keep_valid(1'b0),.keep_slot(2'd0),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.frame_commit(frame_commit),
        .decode_error(decode_error),.load_busy(loader_busy),.load_done(loader_load_done),
        .image_complete(complete),.memory_error(loader_memory_error),
        .controller_init_done(!rst),.controller_busy(1'b0),.refresh_active(1'b0),
        .app_wr_en(we),.app_wr_addr(addr),.app_wr_mask(mask),.app_wr_data(data)
    );

    function [23:0] pattern;
        input integer row,col;
        reg [7:0] pr,pg,pb;
        begin
            pr=(row*3+col*5)&255;pg=(row*7+col*11)&255;pb=(row*13+col*17)&255;
            pattern={pr,pg,pb};
        end
    endfunction
    function [15:0] bcd;
        input integer value;
        begin bcd=((value/1000)%10)*4096+((value/100)%10)*256+((value/10)%10)*16+(value%10);end
    endfunction

    always @(posedge clk) begin
        if(load_start)written=0;
        if(we)begin
            if(check_writes)begin
                ref_oy=written/640;ref_ox=written%640;
                ref_sx=(ref_ox*current_w)/640;ref_sy=(ref_oy*current_h)/480;
                expected_addr=(479-ref_oy)*640+ref_ox;
                if(addr!==expected_addr || data!=={8'd0,pattern(ref_sy,ref_sx)} || mask!==0)begin
                    if(errors<10)$display("FAIL write %0d addr=%0d expected=%0d data=%h expected=%h",
                        written,addr,expected_addr,data,{8'd0,pattern(ref_sy,ref_sx)});
                    errors=errors+1;
                end
            end
            written=written+1;
        end
        if(loader_load_done)done_count=done_count+1;
    end

    task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
    task send_byte;input [7:0] value;begin @(negedge clk);byte_in=value;byte_valid=1;end endtask
    task send16;input [15:0] value;begin send_byte(value[7:0]);send_byte(value[15:8]);end endtask
    task send32;input [31:0] value;begin send_byte(value[7:0]);send_byte(value[15:8]);send_byte(value[23:16]);send_byte(value[31:24]);end endtask
    task send_header;
        input integer w,h,offset,bpp,compression;
        input top_down;
        integer stride,image_file_size;
        begin
            stride=((w*3+3)/4)*4;image_file_size=offset+stride*h;
            send_byte(8'h42);send_byte(8'h4d);send32(image_file_size);send32(0);
            send32(offset);send32(40);send32(w);send32(top_down?-h:h);
            send16(1);send16(bpp);send32(compression);send32(0);
            send32(0);send32(0);send32(0);send32(0);
        end
    endtask
    task pulse_file_done;
        begin
            @(negedge clk);byte_valid=0;streamer_file_done=1;
            @(negedge clk);streamer_file_done=0;
        end
    endtask
    task wait_load;
        begin wait(load_start);wait(!load_start);end
    endtask
    task reload;
        begin
            @(negedge clk);scan_done_latched=0;cache_invalidate=1;tick(2);
            cache_invalidate=0;written=0;tick(3);scan_done_latched=1;
        end
    endtask
    task check_equal;
        input integer actual,expected;input [191:0] label;
        begin if(actual!==expected)begin $display("FAIL %0s actual=%0d expected=%0d",label,actual,expected);errors=errors+1;end end
    endtask
    task send_valid_image;
        input integer w,h,offset;
        integer row,col,pad;
        begin
            current_w=w;current_h=h;pad=w%4;wait_load();
            send_header(w,h,offset,24,0,0);
            for(row=54;row<offset;row=row+1)send_byte(8'ha5);
            for(row=0;row<h;row=row+1)begin
                for(col=0;col<w;col=col+1)begin
                    send_byte(pattern(row,col)&255);
                    send_byte((pattern(row,col)>>8)&255);
                    send_byte((pattern(row,col)>>16)&255);
                end
                for(col=0;col<pad;col=col+1)send_byte(8'hde+col);
            end
            pulse_file_done();
        end
    endtask
    task send_truncated_native;
        integer col;
        begin
            current_w=640;current_h=480;wait_load();send_header(640,480,54,24,0,0);
            for(col=0;col<100;col=col+1)begin
                send_byte(pattern(0,col)&255);send_byte((pattern(0,col)>>8)&255);send_byte((pattern(0,col)>>16)&255);
            end
            pulse_file_done();
        end
    endtask

    initial begin
        tick(4);rst=0;tick(2);sd_init_done=1;scan_done_latched=1;
        check_writes=1;send_valid_image(641,481,54);wait(sd_free);tick(5);
        check_equal(written,307200,"high-res writes");check_equal(complete,1,"high-res complete");
        check_equal(loader_memory_error,0,"high-res loader error");
        check_equal(boot.meta_valid,1,"high-res metadata valid");
        check_equal(boot.meta_w0,bcd(641),"high-res width BCD");
        check_equal(boot.meta_h0,bcd(481),"high-res height BCD");

        reload();check_writes=0;wait_load();send_header(640,480,54,32,0,0);
        @(negedge clk);byte_valid=0;wait(sd_free);tick(5);
        check_equal(complete,0,"invalid BMP not complete");check_equal(written,0,"invalid BMP writes");
        check_equal(boot.meta_valid,0,"invalid BMP metadata");check_equal(boot.err_code,2,"invalid BMP error code");

        reload();check_writes=0;send_truncated_native();
        check_writes=1;send_valid_image(640,480,54);wait(sd_free);tick(5);
        check_equal(written,307200,"retry native writes");check_equal(complete,1,"retry native complete");
        check_equal(loader_memory_error,0,"retry native error");check_equal(boot.meta_valid,1,"retry metadata valid");
        check_equal(boot.meta_w0,bcd(640),"retry width BCD");check_equal(boot.meta_h0,bcd(480),"retry height BCD");

        // A stalled byte stream must abort with F after ~1s of silence, and the
        // next legal load must still succeed.  Legal loads with steady bytes
        // never trip this regardless of total duration.
        reload();check_writes=0;wait_load();send_header(1200,1200,54,24,0,0);
        @(negedge clk);byte_valid=0;
        wait(sd_free);tick(5);
        check_equal(boot.err_code,4'hf,"stalled load error code F");
        check_equal(complete,0,"stalled load not complete");
        reload();check_writes=1;send_valid_image(640,480,54);wait(sd_free);tick(5);
        check_equal(written,307200,"post-stall native writes");
        check_equal(complete,1,"post-stall native complete");

        if(errors==0)begin $display("PASS test_pic_load_integration");$finish;end
        else begin $display("FAIL test_pic_load_integration errors=%0d",errors);$fatal(1);end
    end
    initial begin #2000000000;$fatal(1,"pic load integration timeout");end
endmodule
