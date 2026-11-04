from pathlib import Path
import re
top=Path('../../src/user_source/hdl_source/SD/sd_card_bmp.v').read_text(encoding='utf-8')
lock=re.search(r'always @\(posedge clk or posedge rst\)begin\s*if\(rst\)ck_owner.*?(?=playback_checkpoint)',top,re.S)[0]
adapter=re.search(r'sd_sector_adapter u_adapter \(.*?\n\);',top,re.S)[0]
header='''`timescale 1ns/1ps
module checkpoint_bus_fragment(
 input wire clk,rst,ck_want,ck_read_req,arb_sector_req,
 input wire [31:0] ck_read_lba,arb_sector_lba,
 input wire sd_sec_read_data_valid,sd_sec_read_end,sd_sec_read_error,
 input wire [7:0] sd_sec_read_data,
 output reg ck_owner,
 output wire arb_sector_busy,arb_sector_valid,arb_sector_done,
 output wire [7:0] arb_sector_byte,arb_sector_error,
 output wire [8:0] arb_sector_byte_index,
 output wire adapter_busy,adapter_valid,adapter_done,
 output wire [7:0] adapter_byte,adapter_error,
 output wire [8:0] adapter_index,
 output wire sd_sec_read,output wire [31:0] sd_sec_read_addr
);
'''
Path('checkpoint_bus_fragment.v').write_text(header+lock+adapter+'\nendmodule\n',encoding='utf-8')
