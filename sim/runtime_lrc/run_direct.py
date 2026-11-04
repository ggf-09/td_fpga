"""Invoke Icarus' preprocessor and compiler directly.

The installed development-build iverilog.exe driver crashes on exit on this
machine. Every sub-tool exit status and every simulation is checked here.
"""
from pathlib import Path
import subprocess
import os
import sys
import shutil

os.chdir(Path(__file__).resolve().parent)
iverilog=shutil.which('iverilog')
root=Path(iverilog).resolve().parent.parent if iverilog else Path('D:/app/34_iverilog/iverilog')
binpath=root/'lib'/'ivl'
vvp=shutil.which('vvp') or str(root/'bin'/'vvp.exe')
hdl=Path('../../src/user_source/hdl_source')
cases={
 'test_lyric_visibility':[],
 'test_sd_native':['SD/spi_master.v','SD/sd_card_cmd.v','SD/sd_card_sec_read_write.v','SD/sd_card_top.v'],
 'test_shared_streamer':['SD/fat32_file_streamer.v'],
 'test_spi_fast':['SD/spi_master.v'],
 'test_range_stream':['SD/fat32_file_streamer.v'],
 'test_manager_library_font_range':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_manager_scrolling_range':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_lyric_panel_controls':['playback_controls.v'],
 'test_lyric_panel_render':['audio/runtime_lyric_overlay.v','audio/ram32k_dp8.v','audio/ram32k_dp16.v'],
 'test_resume_library':['resume_startup.v','playback_sequence.v','library_neighbor_finder.v','library_page_router.v','media_player_control.v','video_fade_transition.v'],
 'test_native_reader_fifo':['IP/afifo_32_16_256.v'],
 'test_loader_completion':['media_frame_loader.v'],
 'test_pic_decoder':['bmp_pic_decoder.v'],
 'test_pic_load_integration':['bmp_pic_decoder.v','media_frame_loader.v'],
 'test_real_pic_stream':['bmp_pic_decoder.v','media_frame_loader.v'],
 'test_resolution_osd':['resolution_osd_overlay.v'],
 'test_reader_reservation':['media_frame_reader.v','fifo_prefetch_2.v'],
 'test_seek_top':['audio/fat_wav_player.v','SD/fat32_file_streamer.v','resume_startup.v'],
 'test_seek_controls':['playback_controls.v'],
 'test_image_combo_controls':['playback_controls.v'],
 'test_fade_manual_wipe':['video_fade_transition.v'],
 'test_position_clock':['audio/fat_wav_player.v'],
 'test_seek_stream':['SD/fat32_file_streamer.v'],
 'test_menu_overlay':['thumbnail_controller.v'],
 'test_menu_boot':[],
 'test_library_browser':['thumbnail_controller.v'],
 'test_browser_top_integration':['playback_sequence.v','library_neighbor_finder.v','library_page_router.v','media_player_control.v','video_fade_transition.v','thumbnail_controller.v'],
 'test_menu_reader':['media_frame_reader.v','fifo_prefetch_2.v'],
 'test_menu_loader':['media_frame_loader.v'],
 'test_manager_scrolling':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_scrolling_lyrics':['audio/ram32k_dp8.v','audio/ram32k_dp16.v','audio/fat_lrc_loader.v','audio/runtime_lyric_overlay.v'],
 'test_file_streamer_start':['SD/fat32_file_streamer.v'],
 'test_manager_long_lyrics':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_long_lyrics':['audio/ram32k_dp8.v','audio/ram32k_dp16.v','audio/fat_lrc_loader.v','audio/runtime_lyric_overlay.v'],
 'test_sevenseg_global':['SD/seg_decoder.v','SD/seg_scan.v'],
 'test_reader_paging':[],
 'test_library_status':['playback_status_overlay.v'],
 'test_library_top_integration':['playback_sequence.v','library_neighbor_finder.v','library_page_router.v','media_player_control.v','video_fade_transition.v'],
 'test_library_sequence':['playback_sequence.v'],
 'test_library_neighbor':['library_neighbor_finder.v'],
 'test_manager_library_font':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_cover_page_controller':['cover_page_controller.v'],
 'test_library_router':['library_page_router.v'],
 'test_page_route_timing':['library_page_router.v','cover_page_controller.v'],
 'test_video_armed':[],
 'test_library_scanner':['SD/fat32_library_scanner.v'],
 'test_scanner_attributes':['SD/fat32_volume_scanner.v'],
 'test_lrc_loader':['audio/ram32k_dp8.v','audio/fat_lrc_loader.v'],
 'test_title_parser':['audio/ram32k_dp8.v','audio/fat_lrc_loader.v'],
 'test_overlay':['audio/ram32k_dp8.v','audio/ram32k_dp16.v','audio/runtime_lyric_overlay.v'],
 'test_title_overlay':['audio/ram32k_dp8.v','audio/ram32k_dp16.v','audio/runtime_lyric_overlay.v'],
 'test_playback_status':['playback_status_overlay.v'],
 'test_adjust_bar_overlay':['adjust_bar_overlay.v'],
 'test_clean_chain':['playback_status_overlay.v','adjust_bar_overlay.v','resolution_osd_overlay.v','rgb_video_adapter.v'],
 'test_ui_cdc':[],
 'test_manager':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_manager_title':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_manager_banked':['audio/runtime_lyric_manager.v','audio/ram32k_dp8.v','audio/fat_lrc_loader.v','SD/fat32_file_streamer.v','reset_sync.v'],
 'test_spectrum':['promax_audio_spectrum.v','video_timing_ctrl.v'],
 'test_audio_fifo':['audio/fat_wav_player.v'],
 'test_audio_ui_integration':['audio/fat_wav_player.v','playback_status_overlay.v'],
 'test_video_startup':['video_timing_ctrl.v','osd_overlay_24.v','status_osd_overlay.v','rgb_video_adapter.v','video_rgb_to_axis_640x480.v'],
 'test_playback_controls':['playback_controls.v'],
 'test_gesture_realclk':['playback_controls.v'],
 'test_volume_switch':['playback_controls.v'],
 'test_equalizer_controls':['playback_controls.v'],
 'test_music_equalizer':['audio/music_equalizer.v'],
 'test_clip_timeout':['audio/music_equalizer.v'],
 'test_equalizer_osd':['param_osd_overlay.v','video_timing_ctrl.v'],
 'test_playback_volume':['playback_controls.v'],
 'test_playback_sequence':['playback_sequence.v'],
 'test_sequence_integration':['playback_sequence.v'],
 'test_refresh':[],
 'test_refresh_arbitration':[],
}
native_fifo='--native-fifo' in sys.argv
requested=[name for name in sys.argv[1:] if name!='--native-fifo']
if native_fifo and (not requested or any(name not in {'test_menu_reader','test_refresh_arbitration','test_reader_paging'} for name in requested)):
 raise ValueError('--native-fifo supports test_menu_reader, test_refresh_arbitration and test_reader_paging')
if requested:
 cases={name:cases[name] for name in requested}
subprocess.run(['python','make_vectors.py'],check=True)
subprocess.run(['python','prepare_extended_vectors.py'],check=True)
subprocess.run(['python','prepare_scroll_vectors.py'],check=True)
subprocess.run(['python','prepare_menu_boot_test.py'],check=True)
subprocess.run(['python','prepare_menu_overlay_test.py'],check=True)
subprocess.run(['python','prepare_startup_test.py'],check=True)
subprocess.run(['python','prepare_refresh_test.py'],check=True)
subprocess.run(['python','prepare_sequence_integration.py'],check=True)
subprocess.run(['python','prepare_ui_cdc_test.py'],check=True)
subprocess.run(['python','prepare_library_top_test.py'],check=True)
subprocess.run(['python','prepare_video_armed_test.py'],check=True)
subprocess.run(['python','prepare_seek_top_test.py'],check=True)
subprocess.run(['python','make_equalizer_vectors.py'],check=True)
if 'test_resume_library' in cases:subprocess.run(['python','prepare_resume_library_test.py'],check=True)
top_visibility=(hdl/'top_tf_hdmi_audio.v').read_text(encoding='utf-8')
top_visibility=top_visibility.split('// LYRIC_READY_EXPORT_BEGIN',1)[1].split('// LYRIC_READY_EXPORT_END',1)[0]
Path('lyric_visibility_fragment.v').write_text('module lyric_visibility_fragment(sd_card_clk,sdcard_rst_n,lyric_visible,lyric_visible_export);\ninput sd_card_clk,sdcard_rst_n,lyric_visible;\noutput lyric_visible_export;\n'+top_visibility+'\nendmodule\n',encoding='utf-8')
for name,files in cases.items():
 if name=='test_real_pic_stream':subprocess.run(['python','prepare_real_pic_test.py'],check=True)
 test='test_playback_controls.v' if name=='test_playback_volume' else name+'.v'
 sources=['sim_bram32k_def.v',test]+[str(hdl/f) for f in files]
 if name in ['test_lyric_visibility','test_lyric_panel_render']:sources+=['lyric_visibility_fragment.v']
 if name=='test_resume_library':sources+=['resume_library_fragment.v']
 if name=='test_seek_top':sources+=['seek_top_fragment.v']
 if name=='test_menu_boot':sources+=['menu_boot_fragment.v']
 if name=='test_page_route_timing':sources+=['menu_boot_fragment.v']
 if name=='test_video_armed':sources+=['video_armed_fragment.v']
 if name=='test_pic_load_integration':sources+=['menu_boot_fragment.v']
 if name=='test_sevenseg_global':sources+=['sevenseg_top_fragment.v']
 if name=='test_sequence_integration': sources+=['sequence_top_fragment.v']
 if name in ['test_ui_cdc','test_library_status']: sources+=['ui_cdc_top_fragment.v']
 if name in ['test_library_top_integration','test_browser_top_integration']: sources+=['library_top_fragment.v']
 if name=='test_refresh': sources+=['sdr_init_ref_public.v']
 if name=='test_refresh_arbitration':
  sources += ['behavioral_video_fifo.v',str(hdl/'sdram_refresh_guard.v'),str(hdl/'media_sdram_write_cdc.v'),str(hdl/'media_frame_reader.v'),str(hdl/'fifo_prefetch_2.v')]
 if name=='test_menu_reader':sources+=['behavioral_video_fifo.v']
 if name=='test_reader_reservation':sources+=['behavioral_video_fifo_delayed.v']
 if name=='test_reader_paging':
  sources += ['behavioral_video_fifo.v',str(hdl/'media_frame_reader.v'),str(hdl/'fifo_prefetch_2.v')]
 if native_fifo:
  sources=[source for source in sources if not source.startswith('behavioral_video_fifo')]
  sources.append(str(hdl/'IP/afifo_32_16_256.v'))
 cfg=Path(name+'.direct.cfg')
 modules=''.join(f'module:{binpath/m}\n' for m in ['system.vpi','v2005_math.vpi','va_math.vpi','v2009.vpi'])
 cfg.write_text(f'root:{name}\nbasedir:{binpath}\n{modules}generation:2012\nout:{name}.direct.vvp\niwidth:32\nwidthcap:65536\n',encoding='ascii')
 pre=Path(name+'.direct.v')
 subprocess.run([str(binpath/'ivlpp.exe'),'-L','-o',str(pre),*sources],check=True)
 subprocess.run([str(binpath/'ivl.exe'),'-C',str(cfg),'-C',str(binpath/'vvp.conf'),str(pre)],check=True)
 subprocess.run([vvp,name+'.direct.vvp'],check=True)
 if name=='test_real_pic_stream':
  for variant in ['+pic2','+pic3']:
   subprocess.run([vvp,name+'.direct.vvp',variant],check=True)
  print('CHECKED',name,'pic2+pic3',flush=True)
 print('CHECKED',name,flush=True)
if 'test_music_equalizer' in cases:
 subprocess.run(['python','check_equalizer_response.py'],check=True)
