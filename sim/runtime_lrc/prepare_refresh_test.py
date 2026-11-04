from pathlib import Path
import shutil

root = Path(__file__).resolve().parent
inc = root.parent.parent / 'src/user_source/hdl_source/include'
# Test only the public initialization/refresh scheduler. The protected
# vendor command encoder is not decrypted or included in this unit test.
source = (inc / 'sdr_init_ref.enc.v').read_text(encoding='utf-8')
source = source.split('`pragma protect begin_protected')[0]
source = source.replace('../user_source/hdl_source/include/global_def.v', 'global_def.v')
(root / 'sdr_init_ref_public.v').write_text(source + '\nendmodule\n', encoding='utf-8')
shutil.copyfile(inc / 'global_def.v', root / 'global_def.v')
