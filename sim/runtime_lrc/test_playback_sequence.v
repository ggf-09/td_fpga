`timescale 1ns/1ps
module test_playback_sequence;
 reg clk=0,rst_n=0,mode_next=0,eof=0,manual=0,paused=0,ready=1;
 reg [3:0] playable=4'b0101;
 reg [1:0] current=0;
 wire [1:0] mode,target;
 wire advance,replay,stopped;
 always #5 clk=~clk;
 playback_sequence dut(clk,rst_n,mode_next,eof,manual,paused,ready,playable,current,mode,advance,target,replay,stopped);
 integer advances=0,replays=0,i;
 always @(posedge clk) begin if(advance)advances=advances+1;if(replay)replays=replays+1;end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task change_mode;begin mode_next=1;tick(1);mode_next=0;tick(2);end endtask
 task end_song;begin eof=1;tick(1);eof=0;tick(2);end endtask
 task start_manual;begin manual=1;tick(1);manual=0;tick(2);end endtask
 initial begin
  tick(3);rst_n=1;tick(3);
  tick(2000);if(advances||replays||stopped||mode!=0)$fatal(1,"advanced without EOF");
  end_song();if(advances!=1||target!=2)$fatal(1,"loop failed to skip missing slots");
  current=2;end_song();if(advances!=2||target!=0)$fatal(1,"loop failed to wrap");
  change_mode();if(mode!=1)$fatal(1,"mode2");
  current=0;end_song();if(advances!=3||target!=2)$fatal(1,"ordered next");
  current=2;end_song();tick(20);if(!stopped||advances!=3||replays!=0)$fatal(1,"ordered must stop at end");
  start_manual();if(stopped)$fatal(1,"manual restart after end");
  playable=4'b0100;end_song();if(!stopped)$fatal(1,"one-track ordered must stop");
  change_mode();tick(3);if(mode!=2||stopped||replays!=1)$fatal(1,"random resume single track");
  playable=4'b1101;start_manual();
  for(i=0;i<80;i=i+1)begin
   end_song();
   if(!playable[target]||target==current)$fatal(1,"random picked missing/current slot");
   current=target;tick(i%7+1);
  end
  change_mode();if(mode!=0)$fatal(1,"mode wrap 3 to 1");
  current=0;playable=4'b0101;paused=1;end_song();
  i=advances;tick(30);if(advances!=i)$fatal(1,"EOF advanced while paused");
  ready=0;paused=0;tick(30);if(advances!=i)$fatal(1,"EOF advanced into busy transition");
  ready=1;tick(3);if(advances!=i+1||target!=2)$fatal(1,"lost deferred EOF");
  ready=0;end_song();start_manual();ready=1;tick(10);
  if(advances!=i+1)$fatal(1,"manual selection failed to cancel old EOF");
  playable=0;end_song();if(!stopped)$fatal(1,"empty playlist must stop");
  start_manual();playable=4'b0100;current=2;end_song();
  if(replays!=2)$fatal(1,"one-track loop must replay");
  $display("PASS music modes: EOF-only advance, sparse loop, ordered stop/restart, random no-repeat, single/empty lists, pause/busy deferral, manual cancellation");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
