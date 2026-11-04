`timescale 1ns/1ps
// End-to-end consumed-position/EOF test. The real FIFO/header checker runs
// at its real clock ratio; only sample_tick is accelerated to one in four
// video clocks, so two seconds of sample positions need ~15 ms simulation.
module test_audio_ui_integration;
    reg clk=0,wr_clk=0;
    always #20 clk=~clk;
    always #5 wr_clk=~wr_clk;
    reg rst_n=0,run=0,stream_active=0;
    wire wr_rst_n=rst_n && run;
    wire rd_rst_n=rst_n && stream_active;
    reg vsync=1,de=0,paused=0,stopped=0;
    reg [9:0] pixel_x=0,pixel_y=0;
    reg [23:0] rgb_in=24'h123456;
    reg [1:0] song_index=0,play_mode=0;
    reg [31:0] total_frames=96000;
    reg [1:0] tick_count=0;
    always @(posedge clk) tick_count<=tick_count+1'b1;
    wire sample_tick=(tick_count==0);
    reg file_valid=0,file_done=0;
    reg [7:0] file_byte=0;
    reg [31:0] file_byte_offset=0;
    wire can_read_sector,format_error,stream_end,sample_valid;
    wire signed [15:0] sample_left,sample_right;
    wire [31:0] sample_counter,underflow_count;
    wire [23:0] rgb_out;
    wire osd_active;
    integer checks=0,stalls=0;
    reg [31:0] frozen;
    fat_wav_player #(.ADDR_WIDTH(11)) audio(
        .wr_clk(wr_clk),.wr_rst_n(wr_rst_n),.file_valid(file_valid),
        .file_byte(file_byte),.file_byte_offset(file_byte_offset),
        .file_done(file_done),.file_error(8'd0),.can_read_sector(can_read_sector),
        .format_error(format_error),.stream_end(stream_end),
        .rd_clk(clk),.rd_rst_n(rd_rst_n),.sample_tick(sample_tick),
        .paused(paused),.sample_ready(1'b1),.sample_valid(sample_valid),
        .sample_left(sample_left),.sample_right(sample_right),
        .sample_counter(sample_counter),.underflow_count(underflow_count)
    );
    playback_status_overlay ui(
        .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.rgb_in(rgb_in),
        .sample_count(sample_counter),.total_frames(total_frames),
        .song_index(song_index),.stream_active(stream_active),
        .wav_stream_end(stream_end),.paused(paused),.stopped(stopped),
        .play_mode(play_mode),.rgb_out(rgb_out),.osd_active(osd_active),
        .show_text(1'b1),.transition_active(2'd0)
    );
    function [7:0] wav_byte;
        input integer offset;
        integer data_offset,frame_index;
        begin
            wav_byte=0;
            if(offset<44) case(offset)
                0:wav_byte="R";1:wav_byte="I";2,3:wav_byte="F";
                4:wav_byte=(384000+36)&255;5:wav_byte=((384000+36)>>8)&255;
                6:wav_byte=((384000+36)>>16)&255;
                8:wav_byte="W";9:wav_byte="A";10:wav_byte="V";11:wav_byte="E";
                12:wav_byte="f";13:wav_byte="m";14:wav_byte="t";15:wav_byte=" ";
                16:wav_byte=16;20:wav_byte=1;22:wav_byte=2;
                24:wav_byte=8'h80;25:wav_byte=8'hbb;
                29:wav_byte=8'hee;30:wav_byte=2;32:wav_byte=4;34:wav_byte=16;
                36:wav_byte="d";37:wav_byte="a";38:wav_byte="t";39:wav_byte="a";
                40:wav_byte=384000&255;41:wav_byte=(384000>>8)&255;
                42:wav_byte=(384000>>16)&255;
                default:wav_byte=0;
            endcase else begin
                data_offset=offset-44;frame_index=data_offset/4;
                case(data_offset%4)
                    0:wav_byte=frame_index&255;
                    1:wav_byte=(frame_index>>8)&255;
                    2:wav_byte=(-frame_index)&255;
                    3:wav_byte=((-frame_index)>>8)&255;
                endcase
            end
        end
    endfunction
    task check;
        input condition;
        input [511:0] message;
        begin
            if(!condition) begin $display("FAIL audio/UI: %0s",message);$fatal(1);end
            checks=checks+1;
        end
    endtask
    task snapshot;
        begin
            @(negedge clk);vsync=0;
            repeat(4) @(negedge clk);vsync=1;
            repeat(500) @(negedge clk);
            check(ui.state==0,"UI conversion finishes in vertical blanking");
        end
    endtask
    task write_bytes;
        input integer count;
        input integer complete;
        integer i;
        begin
            @(negedge wr_clk);
            for(i=0;i<count;i=i+1) begin
                if(i%512==0) while(!can_read_sector) begin
                    stalls=stalls+1;file_valid=0;@(negedge wr_clk);
                end
                file_valid=1;file_byte=wav_byte(i);file_byte_offset=i;
                @(negedge wr_clk);
            end
            file_valid=0;file_done=complete;
            @(negedge wr_clk);file_done=0;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;run=1;stream_active=1;
        // Underflow emits silence and does not advance elapsed position.
        repeat(1000) @(negedge clk);snapshot();
        check(sample_counter==0 && underflow_count>0 && ui.progress_pixels==0,
              "underflow wall time does not advance consumed position");
        fork
            write_bytes(384044,1);
            begin
                wait(sample_counter==48000);
                @(negedge clk);paused=1;frozen=sample_counter;
                snapshot();
                check(sample_counter==frozen && frozen==48000,"real FIFO count stays at 48000 while paused");
                check(ui.elapsed_bcd==20'h00001 && ui.total_bcd==20'h00002,
                      "48000 consumed stereo frames format 000:01 of 000:02");
                check(ui.progress_pixels==304 && ui.status_display==1,"actual half-track pause shows half progress");
                repeat(5000) @(negedge clk);snapshot();
                check(sample_counter==48000 && ui.elapsed_bcd==20'h00001 && !stream_end,
                      "paused real audio preserves UI position and cannot EOF");
                while(sample_valid) @(negedge clk);paused=0;
            end
        join
        wait(stream_end);
        repeat(3) @(negedge clk);
        check(sample_counter==96000 && !format_error,"actual complete WAV drains exactly 96000 stereo frames");
        // The actual top drops active/read reset immediately after the EOF
        // handshake. The UI must retain the completed song independently.
        stream_active=0;run=0;stopped=1;
        repeat(5) @(negedge clk);snapshot();
        check(sample_counter==0 && ui.ended && ui.elapsed_bcd==20'h00002 &&
              ui.total_bcd==20'h00002 && ui.progress_pixels==608,
              "real EOF survives FIFO read reset with full time/progress");
        // Replay the same selected song. Even before bytes arrive, the fresh
        // active edge clears the end latch; subsequent data proves FIFO reuse.
        run=1;stream_active=1;stopped=0;snapshot();
        check(!ui.ended && sample_counter==0 && ui.elapsed_bcd==0 && ui.progress_pixels==0,
              "same-song fresh stream resets completed position");
        fork
            write_bytes(44+2048*4,0);
            begin
                wait(sample_counter==1000);@(negedge clk);paused=1;
                snapshot();
                check(sample_counter==1000 && !ui.ended && ui.progress_pixels==6,
                      "replayed WAV updates progress from fresh actual samples");
            end
        join
        check(stalls>0,"real FIFO exercised sector backpressure");
        $display("PASS audio/UI integration: %0d checks; real 96000-frame WAV, pause, EOF/reset retention, same-song replay",checks);
        $finish;
    end
    initial begin #50000000;$fatal(1,"audio/UI timeout");end
endmodule
