`timescale 1ns/1ps
module test_library_sequence;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,mode_next=0,eof=0,manual_start=0,paused=0,route_ready=1;
 reg [15:0] playable=16'hffff;
 reg [3:0] current=0;
 wire [1:0] mode;
 wire advance,replay,stopped;
 wire [3:0] target;
 playback_sequence #(.INDEX_WIDTH(4)) dut(.*);
 integer i,advances=0,replays=0;
 always @(posedge clk)begin if(advance)advances=advances+1;if(replay)replays=replays+1;end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task finish_song;begin eof=1;tick(1);eof=0;tick(24);end endtask
 task change;begin mode_next=1;tick(1);mode_next=0;tick(24);end endtask
 initial begin
  tick(3);rst_n=1;tick(3);
  for(i=1;i<16;i=i+1)begin finish_song();if(target!=i||advances!=i)$fatal(1,"ordered successor %0d missing",i);current=target;end
  finish_song();if(target!=0||advances!=16)$fatal(1,"16 -> 1 loop failed");
  change();finish_song();if(!stopped||advances!=16)$fatal(1,"M2 did not stop after track16");
  manual_start=1;tick(1);manual_start=0;current=0;playable=16'h9001;finish_song();
  if(target!=12||stopped)$fatal(1,"sparse ordered successor above 4 wrong");
  current=12;finish_song();if(target!=15)$fatal(1,"sparse ordered last wrong");
  current=15;finish_song();if(!stopped)$fatal(1,"sparse ordered end wrong");
  change();if(mode!=2||stopped)$fatal(1,"mode resume wrong");current=target;
  for(i=0;i<100;i=i+1)begin
   finish_song();if(!playable[target]||target==current)$fatal(1,"random selected current or missing track");current=target;tick(i%5);
  end
  paused=1;finish_song();i=advances;tick(40);if(advances!=i)$fatal(1,"pause advanced EOF");
  paused=0;route_ready=0;tick(40);if(advances!=i)$fatal(1,"route busy advanced EOF");
  route_ready=1;tick(24);if(advances!=i+1)$fatal(1,"deferred EOF lost");
  // Cancel while the serial scan is still searching.
  playable=16'h8000;current=15;change();eof=1;tick(1);eof=0;tick(3);
  manual_start=1;tick(1);manual_start=0;i=advances;tick(40);
  if(advances!=i||stopped)$fatal(1,"manual choice did not cancel serial search");
  finish_song();if(replays!=1)$fatal(1,"single global track loop did not replay");
  playable=0;finish_song();if(!stopped)$fatal(1,"empty list did not stop");
  $display("PASS serial 16-track sequence: all tracks, sparse pages, loop/ordered/random, pause/busy, in-flight cancellation");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
