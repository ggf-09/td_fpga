`timescale 1ns/1ps
module test_music_equalizer;
 reg clk=0,rst_n=0,clear=0,iv=0,ready=1;
 reg signed [15:0] il=0,ir=0;
 reg [2:0] b=2,m=2,t=2;
 reg [4:0] v=16;
 wire input_ready,ov,clipped;
 wire signed [15:0] ol,orr;
 always #5 clk=~clk;
 music_equalizer #(.CLIP_HOLD_SAMPLES(128)) dut(clk,rst_n,clear,iv,input_ready,il,ir,b,m,t,v,ov,ready,ol,orr,clipped);
 integer f,o,n,rc,l,r,bb,mm,tt,vv,cc,el,er,clip_now,frames=0,clip_remaining=0;
 reg signed [15:0] held_l,held_r;
 initial begin
  f=$fopen("equalizer_vectors.txt","r");o=$fopen("equalizer_results.txt","w");
  if(!f||!o)$fatal(1,"EQ vectors missing");
  repeat(4)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d\n",l,r,bb,mm,tt,vv,cc,el,er,clip_now);
   if(rc!=10)$fatal(1,"bad vector");
   if(cc)begin clear=1;@(negedge clk);clear=0;clip_remaining=0;end
   il=l;ir=r;b=bb;m=mm;t=tt;v=vv;iv=1;ready=1;
   @(posedge clk);
   while(!input_ready)@(posedge clk);
   @(negedge clk);iv=0;
   if(frames%31==0)ready=0;
   wait(ov);@(negedge clk);
   if(ol!==$signed(el)||orr!==$signed(er))$fatal(1,"EQ reference frame=%d got %d/%d expected %d/%d",frames,ol,orr,el,er);
   if(frames<1024&&(ol!==il||orr!==ir))$fatal(1,"neutral EQ not bit-exact");
   if(clip_remaining>0)clip_remaining=clip_remaining-1;
   if(clip_now)clip_remaining=128;
   if(clipped!==(clip_remaining>0))$fatal(1,"clipping hold/expiry status wrong");
   held_l=ol;held_r=orr;
   if(!ready)begin
    repeat(8)begin @(negedge clk);if(!ov||ol!==held_l||orr!==held_r||input_ready)$fatal(1,"output violated backpressure");end
    ready=1;
   end
   $fwrite(o,"%0d %0d\n",ol,orr);
   @(negedge clk);frames=frames+1;
  end
  // Clear an in-flight frame: no stale output or clipping may survive.
  il=32767;ir=-32768;iv=1;@(negedge clk);iv=0;
  repeat(3)@(negedge clk);clear=1;@(negedge clk);clear=0;
  repeat(20)@(negedge clk);if(ov||clipped)$fatal(1,"track reset left stale EQ output");
  $fclose(f);$fclose(o);
  $display("PASS stereo EQ: %0d reference frames, neutral bit-exact, smoothed gains/volume, signed saturation, backpressure and track reset",frames);
  $finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
