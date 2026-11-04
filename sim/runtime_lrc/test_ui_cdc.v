`timescale 1ns/1ps
module test_ui_cdc;
    reg sd_card_clk=0,video_clk=0;
    always #5 sd_card_clk=~sd_card_clk;
    always #20 video_clk=~video_clk;
    reg sdcard_rst=1,video_rst=1,wav_file_start=0;
    reg [1:0] selected_song=0,active_index_pix=0;
    reg [31:0] selected_song_size=0;
    wire [31:0] ui_total_frames;
    integer n;
    ui_cdc_top_fragment dut(.*);
    task start;
        input [1:0] song;
        input [31:0] size;
        begin
            @(negedge sd_card_clk);selected_song=song;selected_song_size=size;wav_file_start=1;
            @(negedge sd_card_clk);wav_file_start=0;
            repeat(6) @(negedge video_clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge video_clk);sdcard_rst=0;video_rst=0;
        repeat(4) @(negedge video_clk);
        if(ui_total_frames!==0) $fatal(1,"duration not zero at reset");
        start(0,44+192000*297);
        if(ui_total_frames!=48000*297) $fatal(1,"duration bundle transfer failed");
        selected_song_size=44+192000*99;
        repeat(10) @(negedge video_clk);
        if(ui_total_frames!=48000*297) $fatal(1,"uncaptured size leaked into video bundle");
        active_index_pix=1;
        #1;if(ui_total_frames!==0) $fatal(1,"new cover used preceding song duration");
        start(1,44+192000*240);
        if(ui_total_frames!=48000*240) $fatal(1,"second track bundle failed");
        start(1,44+192000*12);
        if(ui_total_frames!=48000*12) $fatal(1,"same-song restart missed alternate toggle");
        start(2,32'hfffffffc);
        if(ui_total_frames!==0) $fatal(1,"future song duration leaked before cover commit");
        active_index_pix=2;#1;
        if(ui_total_frames!=32'd1073741812) $fatal(1,"wide duration computation overflowed");
        start(2,44);if(ui_total_frames!=0) $fatal(1,"empty WAV has nonzero duration");
        start(2,40);if(ui_total_frames!=0) $fatal(1,"short WAV size underflowed");
        start(2,48);if(ui_total_frames!=1) $fatal(1,"single stereo-frame WAV mismatch");
        $display("PASS actual top WAV length stable-bundle CDC: switch, replay, gating, wide/empty/short sizes");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
