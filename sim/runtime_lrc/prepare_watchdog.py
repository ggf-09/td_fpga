from pathlib import Path
import re
s=Path('../../src/user_source/hdl_source/SD/sd_card_bmp.v').read_text(encoding='utf-8')
flag=re.search(r'// WATCHDOG_FLAG_BEGIN.*?// WATCHDOG_FLAG_END',s,re.S)[0]
counter=re.search(r'// WATCHDOG_COUNTER_BEGIN.*?// WATCHDOG_COUNTER_END',s,re.S)[0]
header='''`timescale 1ns/1ps
module watchdog_fragment(input wire clk,rst,load_busy,streamer_byte_valid,
 output reg load_abort,output reg [31:0] load_timeout_cnt);
 localparam [31:0] LOAD_STALL_LIMIT=31;
 reg load_timeout_expired;
 reg [7:0] decode_error;reg timeout_abort,source_done_q;
'''
body='''always @(posedge clk or posedge rst)begin
 if(rst)begin load_timeout_cnt<=0;load_abort<=0;decode_error<=0;timeout_abort<=0;source_done_q<=0;end
 else begin load_abort<=0;
'''
Path('watchdog_fragment.v').write_text(header+flag+'\n'+body+counter+'\nend\nend\nendmodule\n',encoding='utf-8')
