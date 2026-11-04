`timescale 1ns/1ps
module test_playback_status;
    reg clk=0; always #20 clk=~clk;
    reg rst_n=0,vsync=1,de=0;
    reg [9:0] pixel_x=0,pixel_y=0;
    reg [23:0] rgb_in=24'h123456;
    reg [31:0] sample_count=0,total_frames=0;
    reg [1:0] song_index=0,play_mode=0;
    reg stream_active=0,wav_stream_end=0,paused=0,stopped=0;
    reg show_text=1;
    reg [1:0] transition_active=0;
    wire [23:0] rgb_out;
    wire osd_active;
    playback_status_overlay dut(.*);
    integer checks=0,n,idx,f;
    reg [31:0] test_total,test_count;
    reg [19:0] expected_bcd;
    function [19:0] time_bcd;
        input [31:0] frames;
        integer secs,mins;
        begin
            secs=frames/48000; mins=secs/60;
            time_bcd={(4'((mins/100)%10)),(4'((mins/10)%10)),(4'(mins%10)),
                      (4'((secs%60)/10)),(4'(secs%10))};
        end
    endfunction
    task check;
        input condition;
        input [511:0] message;
        begin
            if(!condition) begin $display("FAIL: %0s",message);$fatal(1);end
            checks=checks+1;
        end
    endtask
    task frame;
        begin
            @(negedge clk); vsync=0;
            repeat(4) @(negedge clk);
            vsync=1;
            repeat(500) @(negedge clk);
            check(dut.state==0,"blanking computation finished within 500 cycles");
        end
    endtask
    task pixel;
        input [9:0] x,y;
        begin @(negedge clk);pixel_x=x;pixel_y=y;de=1;#1;end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        // Idle/end inputs cannot falsely declare a completed track at reset.
        wav_stream_end=1; frame();
        check(!dut.ended && dut.progress_pixels==0,"zero-length idle file has zero progress");
        wav_stream_end=0;stream_active=1;sample_count=48000*7;frame();
        check(dut.elapsed_bcd==20'h00007 && dut.total_bcd==0 && dut.progress_pixels==0,
              "missing duration preserves elapsed time without false full progress");
        wav_stream_end=0; total_frames=48000*297+123; sample_count=48000*123+456;
        stream_active=1; frame();
        check(dut.elapsed_bcd==20'h00203,"elapsed 123 seconds formatted 002:03");
        check(dut.total_bcd==20'h00457,"total 297 seconds formatted 004:57");
        check(dut.progress_pixels==((64'(sample_count)*608)/total_frames),"fractional progress uses true consumed frames");
        check(dut.status_display==0,"active track shows PLAY");
        pixel(17,470);check(rgb_out==24'h44ddff && osd_active,"progress interior is filled cyan");
        pixel(622,470);check(rgb_out==24'h202028,"unplayed progress remains dark");
        pixel(16,468);check(rgb_out==24'ha0a0a0,"progress border drawn");
        pixel(8,48);check(osd_active,"status row is present");
        pixel(8,56);check(!osd_active && rgb_out==rgb_in,"title area is untouched");
        pixel(320,380);check(!osd_active && rgb_out==rgb_in,"subtitle area is untouched");
        pixel(320,430);check(!osd_active && rgb_out==rgb_in,"spectrum area is untouched");
        de=0;#1;check(!osd_active && rgb_out==rgb_in,"blanking passes through");
        paused=1; frame();
        check(dut.status_display==1 && dut.elapsed_bcd==20'h00203,"pause freezes consumed-time display");
        frame();check(dut.elapsed_bcd==20'h00203,"time does not advance merely with video frames");
        // Completion pulse precedes read-domain reset; full time must persist.
        paused=0; @(negedge clk);wav_stream_end=1;
        repeat(3) @(negedge clk);
        stream_active=0;sample_count=0;stopped=1;
        repeat(3) @(negedge clk);wav_stream_end=0;
        frame();
        check(dut.ended && dut.elapsed_bcd==20'h00457 && dut.progress_pixels==608,"ended song retains full duration after counter reset");
        total_frames=0;frame();
        check(dut.total_bcd==20'h00457 && dut.progress_pixels==608,"ended song keeps captured total if source clears metadata");
        // Replaying the same track clears the completion latch.
        total_frames=48000*297+123;stream_active=1;stopped=0;
        frame();check(!dut.ended && dut.elapsed_bcd==0 && dut.progress_pixels==0,"same-song replay resets completion");
        // Song change also resets ended state and adopts fresh duration/mode.
        stream_active=0;repeat(3) @(negedge clk);
        song_index=1;play_mode=2;total_frames=48000*240;sample_count=48000*120;stream_active=1;
        frame();
        check(dut.song_display==1 && dut.mode_display==2,"song and mode latch on frame boundary");
        check(dut.elapsed_bcd==20'h00200 && dut.total_bcd==20'h00400 && dut.progress_pixels==304,"half progress is exact");
        // Match the actual top: song commit uses a nonblocking update at
        // the very same VS edge sampled by the overlay. Old WAV stays high
        // until SD observes the cover change, and must not leak old time.
        @(negedge clk);vsync=0;
        @(posedge clk);song_index<=2;total_frames<=0;
        repeat(4) @(negedge clk);vsync=1;
        repeat(500) @(negedge clk);
        check(dut.song_display==2 && dut.status_display==3,"same-boundary song commit shows new SONG and LOAD");
        check(!dut.have_stream && dut.elapsed_bcd==0 && dut.progress_pixels==0,
              "old WAV count quarantined while old active level persists");
        // An old EOF arriving during the switch must not complete new song.
        wav_stream_end=1;repeat(3) @(negedge clk);wav_stream_end=0;
        check(!dut.ended,"old EOF cannot complete pending new track");
        stream_active=0;sample_count=0;repeat(4) @(negedge clk);
        total_frames=48000*180;sample_count=48000*3;stream_active=1;frame();
        check(dut.have_stream && dut.status_display==0 && dut.elapsed_bcd==20'h00003 &&
              dut.total_bcd==20'h00300,"fresh active edge accepts new track time and duration");
        // Song and fresh-stream rise may also arrive together.
        stream_active=0;repeat(3) @(negedge clk);
        song_index=3;total_frames=48000*90;sample_count=48000*45;stream_active=1;frame();
        check(dut.song_display==3 && dut.progress_pixels==304 && dut.elapsed_bcd==20'h00045,
              "simultaneous song commit and fresh stream accepted");
        // Wide numerator exercises bit 41; legal FAT32 canonical WAV can
        // exceed 99 minutes, so the UI has three minute digits.
        total_frames=32'h3ffffff0;sample_count=total_frames-1;frame();
        check(dut.total_bcd==time_bcd(total_frames),"long tracks format above 99 minutes");
        check(dut.progress_pixels==607,"wide progress numerator does not overflow");
        sample_count=32'hffffffff;frame();
        check(dut.progress_pixels==608,"overshoot clamps to full progress");
        // Deterministic random positive lengths/counts, including very short
        // tracks. Golden arithmetic lives only in this testbench.
        for(n=0;n<30;n=n+1) begin
            test_total=($random & 32'h3fffffff)+1;
            test_count=($random & 32'h3fffffff)%test_total;
            total_frames=test_total; sample_count=test_count; frame();
            check(dut.elapsed_bcd==time_bcd(test_count),"random consumed-time conversion");
            check(dut.total_bcd==time_bcd(test_total),"random duration conversion");
            check(dut.progress_pixels==(64'(test_count)*608)/test_total,"random progress ratio");
        end
        // Mode legend, transition badge and clean-mode text gating. The
        // character decode uses the display copies latched each frame, so
        // mode changes need one frame; transition_active is combinational.
        // Deterministic partially played track: cyan accent, filled bar head.
        total_frames=48000*297+123;sample_count=48000*123+456;
        stream_active=1;stopped=0;paused=0;
        play_mode=0;frame();
        pixel(8+26*8,48);check(dut.character=="L","LOOP legend missing L");
        pixel(8+27*8,48);check(dut.character=="O","LOOP legend missing O1");
        pixel(8+28*8,48);check(dut.character=="O","LOOP legend missing O2");
        pixel(8+29*8,48);check(dut.character=="P","LOOP legend missing P");
        play_mode=1;frame();
        pixel(8+26*8,48);check(dut.character=="S","SEQ legend missing S");
        pixel(8+27*8,48);check(dut.character=="E","SEQ legend missing E");
        pixel(8+28*8,48);check(dut.character=="Q","SEQ legend missing Q");
        pixel(8+29*8,48);check(dut.character==32,"SEQ legend must be 3 letters");
        play_mode=2;frame();
        pixel(8+26*8,48);check(dut.character=="R","RND legend missing R");
        pixel(8+27*8,48);check(dut.character=="N","RND legend missing N");
        pixel(8+28*8,48);check(dut.character=="D","RND legend missing D");
        pixel(8+29*8,48);check(dut.character==32,"RND legend must be 3 letters");
        // Actual transition badge: 1 = FADE, 2 = WIPE, 0 = blank.
        transition_active=1;
        pixel(8+31*8,48);check(dut.character=="F","FADE badge missing F");
        pixel(8+32*8,48);check(dut.character=="A","FADE badge missing A");
        pixel(8+33*8,48);check(dut.character=="D","FADE badge missing D");
        pixel(8+34*8,48);check(dut.character=="E","FADE badge missing E");
        transition_active=2;
        pixel(8+31*8,48);check(dut.character=="W","WIPE badge missing W");
        pixel(8+32*8,48);check(dut.character=="I","WIPE badge missing I");
        pixel(8+33*8,48);check(dut.character=="P","WIPE badge missing P");
        pixel(8+34*8,48);check(dut.character=="E","WIPE badge missing E");
        transition_active=0;
        pixel(8+31*8,48);check(dut.character==32,"idle transition badge not blank");
        // show_text=0 (clean mode): the y48 text row vanishes but the y468
        // progress bar with its border/fill must survive.
        show_text=0;
        pixel(8,48);check(!osd_active && rgb_out==rgb_in,"clean mode still draws SONG glyph cell");
        pixel(200,52);check(!osd_active && rgb_out==rgb_in,"clean mode still draws time text");
        pixel(280,52);check(!osd_active && rgb_out==rgb_in,"clean mode still draws badge cell");
        pixel(17,470);check(osd_active && rgb_out==24'h44ddff,"clean mode killed progress fill");
        pixel(16,468);check(osd_active && rgb_out==24'ha0a0a0,"clean mode killed progress border");
        pixel(320,470);check(osd_active,"clean mode killed progress bar row");
        show_text=1;
        pixel(8,48);check(osd_active,"text row did not return after clean mode");
        de=0;#1;
        check(dut.progress_pixels==((64'(48000*123+456)*608)/(48000*297+123)),
              "annotation frames disturbed progress arithmetic");
        transition_active=2;play_mode=2;
        f=$fopen("playback_status_preview.ppm","wb");
        $fwrite(f,"P6\n288 8\n255\n");
        for(n=48;n<56;n=n+1)for(idx=0;idx<288;idx=idx+1)begin
            pixel(idx,n);$fwrite(f,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
        end
        $fclose(f);
        $display("PASS playback_status: %0d checks, display isolation, pause, completion, replay, random ratios, LOOP/SEQ/RND legends, FADE/WIPE badges, clean-mode text gating",checks);
        $finish;
    end
    initial begin #50000000; $fatal(1,"timeout");end
endmodule
