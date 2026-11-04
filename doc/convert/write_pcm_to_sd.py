# -*- coding: utf-8 -*-
# 第11课配套：把裸PCM写到SD卡物理扇区（FPGA wav_stream_player 读取位置）
# 默认写到绝对扇区 131072（=64MiB，顶层参数 WAV_START_LBA），
# 并先把整个 18750 扇区（WAV_TOTAL_SECTORS）清零，防止播到旧数据。
# 需要【管理员权限】运行。用法: python write_pcm_to_sd.py E: output.pcm
import sys
import os
import ctypes
from ctypes import wintypes as wt
import subprocess
import argparse
import time

LBA = 131072          # 与顶层 WAV_START_LBA 一致
TOTAL_SECTORS = 18750 # 与顶层 WAV_TOTAL_SECTORS 一致
SECTOR = 512

# ---- Win32 直写物理盘（Vista起已挂载卷禁止直接WriteFile，须先锁定+卸载卷）----
_k32 = ctypes.WinDLL("kernel32", use_last_error=True)
GENERIC_RW = 0x80000000 | 0x40000000          # GENERIC_READ | GENERIC_WRITE
SHARE_RW = 0x1 | 0x2                          # FILE_SHARE_READ | FILE_SHARE_WRITE
OPEN_EXISTING = 3
INVALID_HANDLE = ctypes.c_void_p(-1).value
FSCTL_LOCK_VOLUME     = 0x00090018
FSCTL_UNLOCK_VOLUME   = 0x0009001C
FSCTL_DISMOUNT_VOLUME = 0x00090020

_k32.CreateFileW.restype = wt.HANDLE
_k32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p, wt.DWORD, wt.DWORD, wt.HANDLE]
_k32.DeviceIoControl.restype = wt.BOOL
_k32.DeviceIoControl.argtypes = [wt.HANDLE, wt.DWORD, ctypes.c_void_p, wt.DWORD, ctypes.c_void_p, wt.DWORD,
                                 ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
_k32.SetFilePointerEx.restype = wt.BOOL
_k32.SetFilePointerEx.argtypes = [wt.HANDLE, ctypes.c_int64, ctypes.c_void_p, wt.DWORD]
_k32.WriteFile.restype = wt.BOOL
_k32.WriteFile.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
_k32.CloseHandle.restype = wt.BOOL
_k32.CloseHandle.argtypes = [wt.HANDLE]

def _werr(msg):
    raise OSError(f"{msg} (WinError {ctypes.get_last_error()})")

class RawDiskWriter:
    """锁定并卸载卷后直接写物理盘；用完解锁卷（盘符需拔插或重启才会重新挂载）"""
    def __init__(self, letter, disk_num):
        self.vol = _k32.CreateFileW(rf"\\.\{letter}:", GENERIC_RW, SHARE_RW, None, OPEN_EXISTING, 0, None)
        if self.vol == INVALID_HANDLE:
            _werr(f"打开卷 {letter}: 失败")
        dummy = wt.DWORD(0)
        locked = False
        for _ in range(5):  # 资源管理器等可能短暂占用，重试几次
            if _k32.DeviceIoControl(self.vol, FSCTL_LOCK_VOLUME, None, 0, None, 0, ctypes.byref(dummy), None):
                locked = True
                break
            time.sleep(1)
        if not locked:
            _werr(f"锁定卷 {letter}: 失败（请关闭所有使用该盘的窗口/程序后重试）")
        if not _k32.DeviceIoControl(self.vol, FSCTL_DISMOUNT_VOLUME, None, 0, None, 0, ctypes.byref(dummy), None):
            _werr("卸载卷失败")
        self.disk = _k32.CreateFileW(rf"\\.\PhysicalDrive{disk_num}", GENERIC_RW, SHARE_RW, None, OPEN_EXISTING, 0, None)
        if self.disk == INVALID_HANDLE:
            _werr(f"打开物理盘 {disk_num} 失败")

    def seek(self, offset):
        if not _k32.SetFilePointerEx(self.disk, ctypes.c_int64(offset), None, 0):
            _werr("定位失败")

    def write(self, buf):
        n = wt.DWORD(0)
        if not _k32.WriteFile(self.disk, buf, len(buf), ctypes.byref(n), None):
            _werr("写入失败")
        if n.value != len(buf):
            raise OSError(f"短写: 期望{len(buf)}实际{n.value}")

    def close(self):
        dummy = wt.DWORD(0)
        _k32.DeviceIoControl(self.vol, FSCTL_UNLOCK_VOLUME, None, 0, None, 0, ctypes.byref(dummy), None)
        _k32.CloseHandle(self.disk)
        _k32.CloseHandle(self.vol)

def disk_number_of(drive_letter):
    letter = drive_letter.rstrip(":\\/").upper()
    out = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command",
         f"(Get-Partition -DriveLetter {letter}).DiskNumber"],
        text=True).strip()
    return int(out), letter

def disk_info(num):
    out = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command",
         f"Get-Disk -Number {num} | Select-Object FriendlyName,Size | Format-List"],
        text=True).strip()
    return out

def main():
    ap = argparse.ArgumentParser(description="PCM裸写SD卡物理扇区工具（危险操作）")
    ap.add_argument("drive", help="SD卡盘符（如 E:）")
    ap.add_argument("pcm", help="wav_to_pcm.py 生成的PCM文件")
    ap.add_argument("--lba", type=int, default=LBA, help=f"起始扇区（默认{LBA}）")
    ap.add_argument("--sectors", type=int, default=TOTAL_SECTORS, help=f"区域总扇区（默认{TOTAL_SECTORS}）")
    args = ap.parse_args()

    if not ctypes.windll.shell32.IsUserAnAdmin():
        print('[错误] 需要管理员权限：请右键"以管理员身份运行"终端后重试')
        sys.exit(1)
    if not os.path.exists(args.pcm):
        print(f"[错误] 找不到PCM文件: {args.pcm}")
        sys.exit(1)

    num, letter = disk_number_of(args.drive)
    info = disk_info(num)
    pcm_size = os.path.getsize(args.pcm)
    pcm_sectors = (pcm_size + SECTOR - 1) // SECTOR

    print("=" * 56)
    print(f"目标盘符 {letter}: -> 物理磁盘 {num}")
    print(info)
    print(f"写入文件 {args.pcm} ({pcm_size}字节={pcm_sectors}扇区)")
    print(f"写入位置 扇区 {args.lba} 起（字节偏移 {args.lba * SECTOR}）")
    print(f"先清零整个区域 {args.sectors} 扇区，再写PCM（保证循环边界干净）")
    print("=" * 56)
    if num == 0:
        print("[拦截] 磁盘0通常是系统盘，拒绝写入")
        sys.exit(1)
    if pcm_sectors > args.sectors:
        print(f"[拦截] PCM({pcm_sectors}扇区) 超过区域({args.sectors}扇区)")
        sys.exit(1)
    confirm = input(f"确认对物理磁盘 {num} 进行裸扇区写入？输入 YES 继续: ")
    if confirm.strip() != "YES":
        print("已取消")
        sys.exit(0)

    disk = RawDiskWriter(letter, num)
    try:
        disk.seek(args.lba * SECTOR)
        # 先清零整个音频区
        zeros = bytes(SECTOR * 64)
        remaining = args.sectors * SECTOR
        while remaining > 0:
            chunk = min(remaining, len(zeros))
            disk.write(zeros[:chunk])
            remaining -= chunk
        # 再写PCM
        disk.seek(args.lba * SECTOR)
        with open(args.pcm, "rb") as f:
            while True:
                buf = f.read(SECTOR * 64)
                if not buf:
                    break
                disk.write(buf)
    finally:
        disk.close()

    print(f"完成：{pcm_sectors} 扇区PCM已写入磁盘 {num} 扇区 {args.lba} 起")
    print("注意：卷已被卸载，拔插一次SD卡可重新识别盘符；")
    print("      之后不要再往这张卡拷贝/删除文件（FAT32可能覆盖该区域），")
    print("      如需重拷图片，拷完后重新运行本脚本。")

if __name__ == "__main__":
    main()
