from pathlib import Path
import re
root=Path(__file__).resolve().parent
s=(root/'../../src/user_source/hdl_source/SD/sd_card_bmp.v').read_text(encoding='utf-8')
a=s.index('always @(posedge clk or posedge rst) begin',s.index('// === 第8课：顺序加载状态机（'))
b=s.index('//=== BMP头解析',a)
body=s[a:b]
header="""module menu_boot_fragment(input wire clk,rst,sd_init_done,cache_invalidate,scan_done_latched,
 input wire [3:0] scan_valid_latched,input wire scanner_menu_valid,
 input wire [31:0] scanner_menu_cluster,scanner_menu_size,
 input wire [1:0] requested_slot,
 input wire loader_load_done,input wire [7:0] loader_memory_error,
 input wire streamer_file_done,input wire [7:0] streamer_fs_error,
 input wire streamer_byte_valid,
 input wire decoder_scale_complete,decoder_header_error,decoder_dims_valid,
 input wire [15:0] decoder_width_bcd,decoder_height_bcd,
 output reg menu_ready,load_menu,load_start,output reg [1:0] load_image_index,
 output reg [31:0] load_cluster,load_file_size,output reg load_abort,
 output reg frame_commit,output reg [7:0] decode_error,output wire sd_free);
 localparam MENU_SUPPORT=1,MAX_RETRIES=1;
 localparam [31:0] LOAD_STALL_LIMIT=32'd100_000_000;
 localparam SEQ_IDLE=0,SEQ_KICK=1,SEQ_WAIT=2,SEQ_DONE=3;
 reg [1:0] seq_state,retry_count;reg [2:0] seq_idx;
 reg [1:0] priority_slot;
 wire [1:0] seq_slot=seq_idx[1:0]+priority_slot;
 reg load_busy,timeout_abort,format_abort,source_done_q,menu_attempted;
 reg [31:0] load_timeout_cnt;
 reg load_timeout_expired;
 reg [3:0] err_code,meta_valid;
 reg [15:0] meta_w0,meta_w1,meta_w2,meta_w3,meta_h0,meta_h1,meta_h2,meta_h3;
 wire scanner_scan_done=0;wire [7:0] scanner_fs_error=0;
 wire [2:0] img_found_count={2'b00,scan_valid_latched[0]}+{2'b00,scan_valid_latched[1]}+{2'b00,scan_valid_latched[2]}+{2'b00,scan_valid_latched[3]};
 assign sd_free=seq_state==SEQ_DONE;
 function [31:0] cluster_lut;input [1:0] i;begin cluster_lut=100+i;end endfunction
 function [31:0] size_lut;input [1:0] i;begin size_lut=921654;end endfunction
"""
watchdog=re.search(r'// WATCHDOG_FLAG_BEGIN.*?// WATCHDOG_FLAG_END',s,re.S)[0]
(root/'menu_boot_fragment.v').write_text(header+watchdog+'\n'+body+'\nendmodule\n',encoding='utf-8')
print('Extracted actual boot/page-load sequence FSM')
