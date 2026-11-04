


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Parenthesize macro expressions: without parentheses the nested divide
// expands to 64000000/1000000000/125000000/... and evaluates to zero.
`define   SDR_CLK_PERIOD                 (1000000000 / 125000000)
// init_cnt counts 0..terminal inclusive. 3906 clocks per refresh at 125 MHz
// refresh all 2048 rows in 63.995904 ms (within the 64 ms retention window).
`define   SELF_REFRESH_INTERVAL          ((64000000 / `SDR_CLK_PERIOD / (1 << `ROW_WIDTH)) - 1)

