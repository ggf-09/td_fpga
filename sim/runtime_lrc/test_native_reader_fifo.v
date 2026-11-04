`timescale 1ns/1ps
module test_native_reader_fifo;
 reg rst=1,clkw=0,clkr=0,run_clocks=0,we=0,re=0;
 reg [31:0] di=0;
 wire [31:0] dout;
 wire valid,full_flag,empty_flag;
 wire [8:0] wrusedw,rdusedw;
 rfifo_32_32_512 dut(.rst(rst),.clkw(clkw),.clkr(clkr),.we(we),.di(di),
  .re(re),.dout(dout),.valid(valid),.full_flag(full_flag),.empty_flag(empty_flag),
  .afull(),.aempty(),.wrusedw(wrusedw),.rdusedw(rdusedw));
 always #4 if(run_clocks)clkw=~clkw;
 always #7 if(run_clocks)clkr=~clkr;
 integer w,r,g,phase=0,ticks=0,puts=0,gets=0,full_blocks=0,empty_blocks=0;
 integer before_drain,total_checked=0;
 reg [8:0] fp,fr,gray;
 reg [31:0] queue[0:65535];
 reg [31:0] random_w=32'h12345678,random_r=32'h56781234;
 always @(posedge rst)begin puts=0;gets=0;end
 always @(negedge clkw)begin
  random_w={random_w[30:0],random_w[31]^random_w[21]^random_w[1]^random_w[0]};
  we=!rst && (phase==1 || (phase==2 && random_w[1:0]!=0));
  di=32'hcafe0000+puts;
 end
 always @(negedge clkr)begin
  random_r={random_r[30:0],random_r[31]^random_r[21]^random_r[1]^random_r[0]};
  re=!rst && (phase==3 || (phase==2 && random_r[2:0]<5));
 end
 always @(posedge clkw)if(!rst&&!dut.wr_rst)begin
  if(we&&!full_flag)begin queue[puts]=di;puts=puts+1;end
  if(we&&full_flag)full_blocks=full_blocks+1;
  if(puts-gets>511)$fatal(1,"FIFO overrun");
 end
 always @(posedge clkr)begin
  if(!rst&&!dut.rd_rst&&re&&empty_flag)empty_blocks=empty_blocks+1;
  #1;
  if(!rst&&!dut.rd_rst&&valid)begin
   if(gets>=puts)$fatal(1,"FIFO underrun");
   if(dout!==queue[gets])$fatal(1,"FIFO order mismatch at %0d: %h != %h",gets,dout,queue[gets]);
   gets=gets+1;total_checked=total_checked+1;
  end
 end
 initial begin
  // Exhaust every write/read pointer pair, including ring wrap, against
  // integer occupancy rather than the implementation's pointer expression.
  force dut.wr_addr=fp;
  force dut.rd_to_wr_addr=fr;
  for(w=0;w<512;w=w+1)for(r=0;r<512;r=r+1)begin
   fp=w;fr=r;#1;
   if(full_flag!==(((w-r+512)%512)==511))$fatal(1,"full flag mismatch %0d %0d",w,r);
  end
  for(g=0;g<512;g=g+1)begin
   gray=g^(g>>1);
   if(dut.rd_to_wr_cross_inst.gray2bin(gray)!==g[8:0])$fatal(1,"Gray decode mismatch");
  end
  release dut.wr_addr;release dut.rd_to_wr_addr;
  run_clocks=1;rst=0;#1;rst=1;#100;rst=0;phase=1;
  repeat(900)@(posedge clkw);
  if(!full_flag||puts!=511)$fatal(1,"full boundary not reached");
  phase=2;
  repeat(22000)@(posedge clkw);
  // Cancel an in-progress FIFO session and exercise reset release again.
  phase=0;rst=1;#100;rst=0;phase=2;
  repeat(22000)@(posedge clkw);
  phase=3;
  repeat(5)@(posedge clkw);
  before_drain=puts;
  repeat(1500)@(posedge clkr);
  if(gets!=puts||puts!=before_drain||!empty_flag)$fatal(1,"drain incomplete");
  if(full_blocks==0||empty_blocks==0||total_checked<15000)$fatal(1,"coverage incomplete");
  $display("PASS native reader FIFO: 262144 pointer pairs, 512 Gray values, asynchronous data order, full/empty stalls, repeated wrap and reset; %0d words checked",total_checked);
  $finish;
 end
 initial begin #2000000;$fatal(1,"native FIFO test timeout");end
endmodule
