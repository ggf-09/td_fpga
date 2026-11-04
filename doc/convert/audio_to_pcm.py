# -*- coding: utf-8 -*-
# 第11课配套：任意音频(flac/mp3/wav/ogg...) -> 裸PCM 转换器
# 依赖 soundfile（自带libsndfile）。输出与 wav_to_pcm.py 相同：
# 16bit 有符号小端、48kHz、单声道原始PCM（无文件头）
# 用法: python audio_to_pcm.py input.flac [output.pcm] [-s 秒数上限]
import sys
import audioop
import argparse

MAX_SECTORS = 18750          # 与顶层 WAV_TOTAL_SECTORS 参数一致（≈100秒）
SECTOR = 512
BYTES_PER_SEC = 48000 * 2    # 48kHz × 16bit 单声道 = 187.5 扇区/秒

def main():
    ap = argparse.ArgumentParser(description="任意音频转FPGA裸PCM工具(需soundfile)")
    ap.add_argument("input", help="输入音频文件（flac/mp3/wav/ogg等）")
    ap.add_argument("output", nargs="?", default="output.pcm", help="输出PCM文件（默认 output.pcm）")
    ap.add_argument("-s", "--seconds", type=float, default=MAX_SECTORS * SECTOR / BYTES_PER_SEC,
                    help="截取时长秒数（默认100秒=18750扇区，与工程参数一致）")
    args = ap.parse_args()

    try:
        import soundfile as sf
    except ImportError:
        print("[错误] 需要 soundfile: python -m pip install soundfile")
        sys.exit(1)

    try:
        data, fr = sf.read(args.input, dtype="int16", always_2d=True)
    except Exception as e:
        print(f"[错误] 解码失败: {e}")
        sys.exit(1)

    ch = data.shape[1]
    n = data.shape[0]
    print(f"输入: {args.input}  声道={ch} 位深=16bit 采样率={fr}Hz 帧数={n} ({n/fr:.1f}秒)")

    frames = data.tobytes()  # int16 小端交错

    # 混单声道 -> 重采样到48k
    if ch != 1:
        frames = audioop.tomono(frames, 2, 0.5, 0.5)
    if fr != 48000:
        frames, _ = audioop.ratecv(frames, 2, 1, fr, 48000, None)

    # 截取时长 & 截到整扇区
    max_bytes = int(args.seconds * BYTES_PER_SEC)
    frames = frames[:max_bytes]
    frames = frames[:len(frames) // SECTOR * SECTOR] if len(frames) >= SECTOR else frames
    sectors = (len(frames) + SECTOR - 1) // SECTOR

    with open(args.output, "wb") as f:
        f.write(frames)

    print(f"输出: {args.output}  {len(frames)} 字节 = {sectors} 扇区 ({len(frames)/BYTES_PER_SEC:.1f}秒)")
    if sectors > MAX_SECTORS:
        print(f"[警告] 超过工程参数 WAV_TOTAL_SECTORS={MAX_SECTORS}，请用 -s 缩短或改大顶层参数重编译")
    else:
        print(f"未超工程上限({MAX_SECTORS}扇区)，可直接写卡")

if __name__ == "__main__":
    main()
