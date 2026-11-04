from pathlib import Path
import re
root=Path(__file__).resolve().parent
s=(root/'library_top_fragment.v').read_text(encoding='utf-8')
top=(root/'../../src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
s=s.replace('module library_top_fragment(','module resume_library_fragment(',1)
s=s.replace(' input wire sd_card_clk,',' input wire checkpoint_boot_ready,checkpoint_restore_valid,\n input wire [3:0] checkpoint_restore_track,\n input wire [31:0] checkpoint_restore_frame,checkpoint_restore_size,checkpoint_restore_cluster,\n input wire sd_card_clk,',1)
old=re.search(r'^wire resume_hold_audio=.*?;$',s,re.M)[0]
new="""wire resume_hold_audio,resume_position_ok,resume_apply,resume_position_ready,resume_ready,resume_route_request;
wire resume_position_valid;wire [3:0] resume_route_target;wire [31:0] resume_start_offset;
wire [31:0] selected_song_size=4000044,selected_song_cluster=10+{library_cache_page,selected_song};
"""
validation=top.split('// RESUME_VALIDATION_BEGIN')[1].split('// RESUME_VALIDATION_END')[0]
validation=validation[validation.index('resume_file_validator'):]
coordinator=top.split('wire resume_consumed=')[1].split('// Transfer position')[0]
new+='assign resume_position_ok=resume_apply && resume_position_ready && resume_position_valid;\n'+validation+'\nwire resume_consumed='+coordinator
assert s.count(old)==1
declarations,logic=new.split('assign resume_position_ok=',1)
s=s.replace(old,declarations,1)
s=s.rsplit('endmodule',1)[0]+'assign resume_position_ok='+logic+'\nendmodule\n'
(root/'resume_library_fragment.v').write_text(s,encoding='utf-8')
print('Extracted actual top startup coordinator/validator with router, video fade, commits and WAV startup FSM')
