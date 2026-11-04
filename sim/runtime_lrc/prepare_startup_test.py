from pathlib import Path
import re

root = Path(__file__).resolve().parent
top = (root / '../../src/user_source/hdl_source/top_tf_hdmi_audio.v').resolve()
source = top.read_text(encoding='utf-8')
adapter = source.split(') u_video_adapter (', 1)[1].split(');', 1)[0]
connection = re.search(r'\.de_in\s*\(([^()]*)\)', adapter).group(1)
# Exercise the actual top-level connection, including the former image gate.
(root / 'startup_de_connection.vh').write_text(
    f'wire adapter_de = {connection};\n', encoding='utf-8')
