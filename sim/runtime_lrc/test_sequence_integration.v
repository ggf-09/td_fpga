`timescale 1ns/1ps
module test_sequence_integration;
 reg clk=0,rst=1,eos=0,mode_next=0,paused=0,busy=0,manual=0,same=0;
 reg [3:0] slots=4'b0101;
 reg [1:0] active=0;
 wire playing,start,advance,replay,stopped;
 wire [1:0] selected,target,mode;
 integer starts=0,advances=0;
 always #5 clk=~clk;
 sequence_top_fragment dut(clk,rst,eos,mode_next,paused,busy,manual,same,slots,active,playing,start,selected,target,mode,advance,replay,stopped);
 always @(posedge clk) begin
  if(start)starts=starts+1;
  if(advance)advances=advances+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task end_song;begin eos=1;tick(8);eos=0;end endtask
 initial begin
  tick(4);rst=0;tick(12);if(!playing||starts!=1)$fatal(1,"initial song");
  tick(500);if(starts!=1||advances!=0)$fatal(1,"wall-clock restart");
  end_song();tick(1100);if(!advance&&advances!=1)$fatal(1,"EOF advance missing");
  if(target!=2||playing)$fatal(1,"audio restarted before cover change");
  active=target;tick(12);if(!playing||selected!=2||starts!=2)$fatal(1,"cover-song synchronization");
  mode_next=1;tick(1);mode_next=0;
  end_song();tick(1100);if(!stopped||playing||starts!=2)$fatal(1,"ordered end restarted");
  manual=1;same=1;tick(1);manual=0;same=0;tick(12);
  if(!playing||stopped||starts!=3)$fatal(1,"manual replay after ordered stop");
  // A manual same-track choice during the EOF reset interval must cancel
  // the queued automatic next song and still restart after the transition.
  end_song();tick(20);busy=1;manual=1;same=1;tick(1);manual=0;same=0;
  tick(1100);if(playing||starts!=3)$fatal(1,"manual replay ignored transition");
  busy=0;tick(12);if(!playing||starts!=4||advances!=1)$fatal(1,"stale EOF overrode manual replay");
  // Single-track looping restarts exactly once, after reset/CDC settlement.
  slots=4'b0100;mode_next=1;tick(1);mode_next=0;tick(2);
  mode_next=1;tick(1);mode_next=0;tick(2);
  end_song();tick(1100);if(!playing||starts!=5)$fatal(1,"single-track loop failed");
  tick(1100);if(starts!=5)$fatal(1,"stale EOF caused repeated restarts");
  $display("PASS actual top FSM/sequence integration: EOF waits, cover commit, ordered stop, manual replay/race cancellation, single-track restart without stale EOF");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
