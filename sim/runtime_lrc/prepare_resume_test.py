from pathlib import Path
s=Path('test_seek_top.v').read_text(encoding='utf-8')
s=s[:s.index(' initial begin\n  repeat(5)')].replace('module test_seek_top;','module test_resume_transport;')
s+=''' initial begin
  force dut.resume_hold_audio=1;
  repeat(5)@(negedge sd_card_clk);sdcard_rst=0;video_rst=0;
  repeat(50)@(negedge sd_card_clk);if(wav_play_en || starts!=0)$fatal(1,"audio before restore");
  accepted_manual=1;manual_same_song=1;@(negedge sd_card_clk);accepted_manual=0;manual_same_song=0;
  force dut.resume_apply=1;force dut.checkpoint_restore_frame=480123;
  release dut.resume_hold_audio;
  wait(wav_file_start);@(negedge sd_card_clk);release dut.resume_apply;release dut.checkpoint_restore_frame;
  wait(checked>100);repeat(200)@(negedge video_clk);
  if(dut.wav_origin_pix!=480123 || dut.wav_start_offset!=1920536)$fatal(1,"restored offset");
  if(dut.manual_replay_pending || dut.manual_eof_cancel)$fatal(1,"startup manual route contaminated playback session");
  if(lyric_cs!=wav_position/480 || starts!=1)$fatal(1,"restored lyric clock/restart count");
  $display("PASS production WAV recovery: boot audio hold, exact restored frame/byte offset, fragmented FAT, first PCM frame and lyric clock");$finish;
 end
 initial begin #10000000;$fatal(1,"restore timeout");end
endmodule
'''
Path('test_resume_transport.v').write_text(s,encoding='utf-8')
