from pathlib import Path
import subprocess,os,shutil,struct,zlib
os.chdir(Path(__file__).resolve().parent)
iv=Path('D:/app/34_iverilog/iverilog/lib/ivl')
def run(name,sources):
 cfg=Path(name+'.cfg')
 cfg.write_text(f'root:{name}\nbasedir:{iv}\n'+''.join(f'module:{iv/m}\n' for m in ['system.vpi','v2005_math.vpi','va_math.vpi','v2009.vpi'])+f'generation:2012\nout:{name}.vvp\niwidth:32\nwidthcap:65536\n',encoding='ascii')
 subprocess.run([str(iv/'ivlpp.exe'),'-L','-o',name+'.pre.v',*sources],check=True)
 subprocess.run([str(iv/'ivl.exe'),'-C',str(cfg),'-C',str(iv/'vvp.conf'),name+'.pre.v'],check=True)
 subprocess.run([str(iv.parent.parent/'bin/vvp.exe'),name+'.vvp'],check=True)
records=[]
for gen,frame in [(3,480000),(0,620000)]:
 payload=struct.pack('<IIIIII',0x314d5352,gen,12,frame,4000044,30); crc=zlib.crc32(payload); records.append(payload+struct.pack('<II',crc,crc^0xffffffff)+bytes(480))
Path('checkpoint_wrap.hex').write_text(''.join(f'{b:02x}\n' for b in b''.join(records)),encoding='ascii')
run('test_checkpoint',['test_checkpoint.v','../../src/user_source/hdl_source/SD/playback_checkpoint.v'])
data=bytes(int(line,16) for line in Path('checkpoint_saved.hex').read_text().splitlines() if not line.startswith('//'))
assert data[:4]==b'RSM1'
crc,inv=struct.unpack_from('<II',data,24)
assert crc==zlib.crc32(data[:24]) and inv==crc^0xffffffff
assert struct.unpack_from('<IIIII',data,4)==(1,12,480000,4000044,30)
print('PASS independent Python zlib CRC32 and little-endian record layout')

run('test_resume_startup',['test_resume_startup.v','../../src/user_source/hdl_source/resume_startup.v'])

subprocess.run(['python','prepare_seek_top_test.py'],check=True)
subprocess.run(['python','prepare_resume_test.py'],check=True)
run('test_resume_transport',['sim_bram32k_def.v','test_resume_transport.v','seek_top_fragment.v','../../src/user_source/hdl_source/resume_startup.v','../../src/user_source/hdl_source/audio/fat_wav_player.v','../../src/user_source/hdl_source/SD/fat32_file_streamer.v'])

run('test_sd_write',['test_sd_write.v','../../src/user_source/hdl_source/SD/sd_card_cmd.v'])

run('test_checkpoint_scanner',['test_checkpoint_scanner.v','../../src/user_source/hdl_source/SD/fat32_library_scanner.v'])

run('test_checkpoint_cdc',['test_checkpoint_cdc.v','../../src/user_source/hdl_source/resume_startup.v'])

subprocess.run(['python','prepare_checkpoint_bus.py'],check=True)
run('test_checkpoint_bus',['test_checkpoint_bus.v','checkpoint_bus_fragment.v','../../src/user_source/hdl_source/SD/sd_sector_adapter.v'])

run('test_resume_validator',['test_resume_validator.v','../../src/user_source/hdl_source/resume_startup.v'])

subprocess.run(['python','prepare_watchdog.py'],check=True)
run('test_watchdog',['test_watchdog.v','watchdog_fragment.v'])

run('test_sd_write_controller',['test_sd_write_controller.v','../../src/user_source/hdl_source/SD/sd_card_sec_read_write.v'])
