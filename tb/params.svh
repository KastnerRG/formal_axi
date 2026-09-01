`ifndef FRAMEWORK_PARAMS_SVH
`define FRAMEWORK_PARAMS_SVH

`ifndef AXI_ADDR_W
`define AXI_ADDR_W 32
`endif
`ifndef AXI_DATA_W
`define AXI_DATA_W 32
`endif
`ifndef AXI_ID_W
`define AXI_ID_W 4
`endif
`ifndef AXI_USER_W
`define AXI_USER_W 1
`endif

// AXI4 normal-transaction MVP profile.  These are configuration contracts,
// not architectural AXI limits.
`ifndef AXI_MAX_AW_AHEAD
`define AXI_MAX_AW_AHEAD 4
`endif
`ifndef AXI_MAX_W_AHEAD
`define AXI_MAX_W_AHEAD 4
`endif
`ifndef AXI_MAX_BURST_LEN
`define AXI_MAX_BURST_LEN 8
`endif
`ifndef AXI_ENABLE_TRANSACTION_FVIP
`define AXI_ENABLE_TRANSACTION_FVIP 1
`endif

`ifndef AXI_F_LGDEPTH
`define AXI_F_LGDEPTH 16
`endif
`ifndef AXI_F_AXI_MAXSTALL
`define AXI_F_AXI_MAXSTALL 10000
`endif
`ifndef AXI_F_AXI_MAXRSTALL
`define AXI_F_AXI_MAXRSTALL 10000
`endif
`ifndef AXI_F_AXI_MAXDELAY
`define AXI_F_AXI_MAXDELAY 10000
`endif

`endif
