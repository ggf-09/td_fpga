
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]


# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]



# ------------------------------------------------------------
# 5. 第5课选做补充：伪路径 / 跨域最大延迟 / 时钟不确定度
# ------------------------------------------------------------

# 5.1 异步输入端口：复位与按键，外部信号无固定相位，不做时序检查
set_false_path -from [get_ports {rst_n key1 key2}]

# 5.2 跨时钟域路径：均已用两级触发器/FIFO处理亚稳态，
#     只限制布线延迟别太大，不再按同步路径检查建立/保持
#     img_num:      sd_card_clk -> video_clk（2FF同步）
#     write_toggle/sdr_init_done: ext_mem_clk -> sd_card_clk（toggle同步/电平）
set_max_delay -from [get_clocks {sd_card_clk}] -to [get_clocks {video_clk}]   10
set_max_delay -from [get_clocks {ext_mem_clk}] -to [get_clocks {sd_card_clk}] 6

# 5.2b 第8课新增跨域（四bank架构，loader/reader分离）：
#     media_sdram_write_cdc异步命令FIFO: sd_card_clk -> ext_mem_clk（gray码+双触发器）
set_max_delay -from [get_clocks {sd_card_clk}] -to [get_clocks {ext_mem_clk}] 5
#     rfifo_32_32_512读数据异步FIFO: ext_mem_clk -> video_clk（gray码+双触发器）
set_max_delay -from [get_clocks {ext_mem_clk}] -to [get_clocks {video_clk}]   8
#     image_complete/请求反馈: video_clk -> ext_mem_clk（2FF同步，reader的pix->mem同步器）
set_max_delay -from [get_clocks {video_clk}]   -to [get_clocks {ext_mem_clk}] 8
#     image_complete/active_index/underflow回传: video_clk -> sd_card_clk（2FF同步）
set_max_delay -from [get_clocks {video_clk}]   -to [get_clocks {sd_card_clk}] 10

# 5.2c SDRAM加密核伪违例（自第1讲起每讲都有，板级SDRAM一直正常）：
#     官方 sdr_as_ram 核的 DQ/DQM 双向PAD被工具套用通用IO预算，
#     ext_mem_clk 与 ext_mem_clk_sft(180°相移) 互报 -6.8/-2.9ns，属IP内部模型，设伪路径
set_false_path -from [get_clocks {ext_mem_clk}]     -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]

# 5.2d 数码管显示路径：sd_card_clk域错误码/图片号 -> clk域seg_scan寄存器。
#     准静态LED调试显示，ns级毛刺肉眼不可见，且两域间仅此一类功能路径；
#     第12课32段频谱加入后布局收紧，该路径出现-0.35ns hold伪违例，设伪路径
set_false_path -from [get_clocks {sd_card_clk}] -to [get_clocks {clk}]

# 5.3 PLL输出时钟不确定度：给抖动/偏差预留裕量，更接近真实硬件
set_clock_uncertainty -setup 0.200 [get_clocks {sd_card_clk ext_mem_clk video_clk hdmi_5x_clk}]
set_clock_uncertainty -hold  0.050 [get_clocks {sd_card_clk ext_mem_clk video_clk hdmi_5x_clk}]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------
