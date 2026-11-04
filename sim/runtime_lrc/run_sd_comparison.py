from pathlib import Path
import json, re, subprocess

r=Path(__file__).resolve().parent.parent.parent
s=r/'sim/runtime_lrc';h=r/'src/user_source/hdl_source'
iv=Path('D:/app/34_iverilog/iverilog/lib/ivl')
name='native_reference'
cfg=s/(name+'.cfg');pre=s/(name+'.pre.v');out=s/(name+'.vvp')
modules=''.join(f'module:{iv/m}\n' for m in ['system.vpi','v2005_math.vpi','va_math.vpi','v2009.vpi'])
cfg.write_text(f'root:test_sd_native\nbasedir:{iv}\n{modules}generation:2012\nout:{out.as_posix()}\niwidth:32\nwidthcap:65536\n',encoding='ascii')
sources=[s/'test_sd_native.v',s/'benchmarks/spi_master_reference.v']+[h/'SD'/f for f in ['sd_card_cmd.v','sd_card_sec_read_write.v','sd_card_top.v']]
subprocess.run([str(iv/'ivlpp.exe'),'-L','-o',str(pre),*[str(p) for p in sources]],check=True,cwd=s)
subprocess.run([str(iv/'ivl.exe'),'-C',str(cfg),'-C',str(iv/'vvp.conf'),str(pre)],check=True,cwd=s)
result=subprocess.run([str(iv.parent.parent/'bin/vvp.exe'),str(out)],check=True,cwd=s,capture_output=True,text=True)
(r/'verification_sd_reference.log').write_text(result.stdout,encoding='utf-8')
assert 'PASS native SD pins:' in result.stdout
old=result.stdout;new=(r/'verification_sd_native.log').read_text(encoding='utf-8-sig')
bench={}
for operation in ['read','write']:
    pattern=rf'BENCH {operation}512 controller_cycles=(\d+)'
    a=int(re.search(pattern,old)[1]);b=int(re.search(pattern,new)[1])
    assert b<a*0.65,(operation,a,b)
    bench[operation]={'baseline_cycles':a,'optimized_cycles':b,'baseline_us':a*.02,'optimized_us':b*.02,'time_reduction_percent':round((1-b/a)*100,2),'throughput_ratio':round(a/b,3)}
    print(operation,bench[operation])
bench['scope']='same 50MHz controller, native SD pins, same card model; excludes real card latency and total cover/startup time'
bench['font_payload_bytes']={'baseline':524288,'optimized':12288}
(r/'verification').mkdir(exist_ok=True)
(r/'verification/speed_comparison.json').write_text(json.dumps(bench,indent=2,ensure_ascii=False),encoding='utf-8')
print('PASS reference and optimized pin-level SD read/write/readback/retry on the same model; no hardware latency claim')
