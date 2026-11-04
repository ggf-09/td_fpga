# -*- coding: utf-8 -*-
# 第11课配套：WAV -> 裸PCM 转换器（FPGA wav_stream_player 专用格式）
# 输出：16bit 有符号小端、48kHz、单声道原始PCM（无文件头）
# 用法: python wav_to_pcm.py input.wav [output.pcm] [-s 秒数上限]
import sys
import wave
import audioop
import argparse

MAX_SECTORS = 18750          # 与顶层 WAV_TOTAL_SECTORS 参数一致（≈100秒）
SECTOR = 512
BYTES_PER_SEC = 48000 * 2    # 48kHz × 16bit 单声道 = 187.5 扇区/秒

def main():
    ap = argparse.ArgumentParser(description="WAV转FPGA裸PCM工具")
    ap.add_argument("input", help="输入WAV文件（PCM格式）")
    ap.add_argument("output", nargs="?", default="output.pcm", help="输出PCM文件（默认 output.pcm）")
    ap.add_argument("-s", "--seconds", type=float, default=MAX_SECTORS * SECTOR / BYTES_PER_SEC,
                    help="截取时长秒数（默认100秒=18750扇区，与工程参数一致）")
    args = ap.parse_args()

    try:
        w = wave.open(args.input, "rb")
    except wave.Error as e:
        print(f"[错误] 读不了该WAV（可能不是PCM编码，如mp3/flac/ADPCM）: {e}")
        sys.exit(1)

    ch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    print(f"输入: {args.input}  声道={ch} 位深={sw*8}bit 采样率={fr}Hz 帧数={n} ({n/fr:.1f}秒)")
    frames = w.readframes(n)
    w.close()

    # 统一成16bit -> 混单声道 -> 重采样到48k
    if sw != 2:
        frames = audioop.lin2lin(frames, sw, 2)
        sw = 2
    if ch != 1:
        frames = audioop.tomono(frames, sw, 0.5, 0.5)
    if fr != 48000:
        frames, _ = audioop.ratecv(frames, sw, 1, fr, 48000, None)

    # 截取时长 & 截到整扇区
    max_bytes = int(args.seconds * BYTES_PER_SEC)
    data = frames[:max_bytes]
    data = data[:len(data) // SECTOR * SECTOR] if len(data) >= SECTOR else data
    sectors = (len(data) + SECTOR - 1) // SECTOR

    with open(args.output, "wb") as f:
        f.write(data)

    print(f"输出: {args.output}  {len(data)} 字节 = {sectors} 扇区 ({len(data)/BYTES_PER_SEC:.1f}秒)")
    if sectors > MAX_SECTORS:
        print(f"[警告] 超过工程参数 WAV_TOTAL_SECTORS={MAX_SECTORS}，请用 -s 缩短或改大顶层参数重编译")
    else:
        print(f"未超工程上限({MAX_SECTORS}扇区)，可直接写卡")

if __name__ == "__main__":
    main()
