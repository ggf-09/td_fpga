// 仿真专用：定义 BRAM32K 行为模型开关（作为编译列表第一个文件传入）。
// TD 综合不传此文件，ram32k_dp8.v 在综合时走 EG_PHY_BRAM32K 原语分支。
`define BRAM32K_BEHAVIORAL 1
