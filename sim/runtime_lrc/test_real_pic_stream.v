`timescale 1ns/1ps
// Feed the exact bytes of the staged hi-res card files through the production
// decoder+loader, with sector-sized bursts and inter-sector gaps like the real
// SD streamer.  Every SDRAM word is compared with an independent integer model.
module test_real_pic_stream;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,start=0;
    reg [31:0] file_size=0;
    reg byte_valid=0;reg [7:0] byte_in=0;
    reg frame_commit=0;reg [7:0] decode_error=0;
    wire pixel_valid;wire [23:0] pixel_rgb;wire [18:0] out_count;
    wire scale_complete,header_error,dims_valid;
    wire [15:0] width_bcd,height_bcd;
    wire loader_busy,load_done,we;wire [3:0] complete,mask;
    wire [7:0] memory_error;wire [20:0] addr;wire [31:0] data;

    reg [7:0] fmem[0:4400000];
    reg [23:0] emem[0:307199];
    integer fsize=0,written=0,errors=0,i,gap;
    integer ref_oy,ref_ox,expected_addr;

    bmp_pic_decoder decoder(
        .clk(clk),.rst(rst),.start(start),.abort(1'b0),.file_size(file_size),
        .byte_valid(byte_valid),.byte_in(byte_in),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.out_count(out_count),
        .scale_complete(scale_complete),.header_error(header_error),
        .src_width_bcd(width_bcd),.src_height_bcd(height_bcd),.dims_valid(dims_valid)
    );
    media_frame_loader loader(
        .clk(clk),.rst_n(!rst),.load_start(start),
        .menu_load(1'b0),.image_index(2'd0),
        .cache_invalidate(1'b0),.keep_valid(1'b0),.keep_slot(2'd0),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.frame_commit(frame_commit),
        .decode_error(decode_error),.load_busy(loader_busy),.load_done(load_done),
        .image_complete(complete),.memory_error(memory_error),
        .controller_init_done(1'b1),.controller_busy(1'b0),.refresh_active(1'b0),
        .app_wr_en(we),.app_wr_addr(addr),.app_wr_mask(mask),.app_wr_data(data)
    );

    always @(posedge clk) begin
        if(start)written=0;
        if(we)begin
            ref_oy=written/640;ref_ox=written%640;
            expected_addr=(479-ref_oy)*640+ref_ox;
            if(addr!==expected_addr[20:0] || data!=={8'd0,emem[expected_addr]} || mask!==0)begin
                if(errors<10)$display("FAIL write %0d addr=%0d expected=%0d data=%h expected=%h",
                    written,addr,expected_addr,data,{8'd0,emem[expected_addr]});
                errors=errors+1;
            end
            written=written+1;
        end
    end

    initial begin
        if($test$plusargs("pic3"))begin
            $readmemh("real_pic3_bytes.hex",fmem);
            $readmemh("real_pic3_expected.hex",emem);
            fsize=3960054;
        end else if($test$plusargs("pic2"))begin
            $readmemh("real_pic2_bytes.hex",fmem);
            $readmemh("real_pic2_expected.hex",emem);
            fsize=3835254;
        end else begin
            $readmemh("real_pic1_bytes.hex",fmem);
            $readmemh("real_pic1_expected.hex",emem);
            fsize=4320054;
        end
        file_size=fsize;
        repeat(4)@(negedge clk);rst=0;repeat(2)@(negedge clk);
        start=1;@(negedge clk);start=0;
        for(i=0;i<fsize;i=i+1)begin
            byte_in=fmem[i];byte_valid=1;@(negedge clk);
            if(i%512==511)begin
                byte_valid=0;byte_in=0;
                for(gap=0;gap<40;gap=gap+1)@(negedge clk);
            end
        end
        byte_valid=0;byte_in=0;
        repeat(2)@(negedge clk);
        if(!scale_complete)begin
            $display("FAIL scale_complete low after file: out_count=%0d",out_count);
            errors=errors+1;
        end
        frame_commit=1;@(negedge clk);frame_commit=0;
        wait(load_done);repeat(5)@(negedge clk);
        if(written!==307200)begin $display("FAIL written=%0d",written);errors=errors+1;end
        if(complete!==1)begin $display("FAIL complete=%0d",complete);errors=errors+1;end
        if(memory_error!==0)begin $display("FAIL memory_error=%h",memory_error);errors=errors+1;end
        if(header_error!==0)begin $display("FAIL header_error");errors=errors+1;end
        if(!dims_valid)begin $display("FAIL dims_valid");errors=errors+1;end
        if(errors==0)begin
            $display("PASS real pic stream: %0d bytes -> %0d checked SDRAM words, BCD %h x %h",
                fsize,written,width_bcd,height_bcd);
            $finish;
        end
        $display("FAIL real pic stream errors=%0d",errors);$fatal(1);
    end
    initial begin #400000000;$fatal(1,"real pic stream timeout");end
endmodule
