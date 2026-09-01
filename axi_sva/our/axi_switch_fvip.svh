// Default is AXI_MASTER, to drive a slave

`ifdef MASTER
  `define MODNAME_AXI m_axi_fvip
  `define MODNAME_TXN m_axi_transaction_fvip
  `define MODNAME_READ_TRACKER m_axi_read_tracker
  `define MODNAME_PAIR_TRACKER m_axi_pair_tracker
  `define MODNAME_WRITE_TRACKER m_axi_write_tracker
  `define TXN_SOURCE  assume
  `define TXN_DEST    assert
`else
  `define MODNAME_AXI s_axi_fvip
  `define MODNAME_TXN s_axi_transaction_fvip
  `define MODNAME_READ_TRACKER s_axi_read_tracker
  `define MODNAME_PAIR_TRACKER s_axi_pair_tracker
  `define MODNAME_WRITE_TRACKER s_axi_write_tracker
  `define TXN_SOURCE  assert
  `define TXN_DEST    assume
`endif

`include "axi_read_tracker.sv"
`include "axi_pair_tracker.sv"
`include "axi_write_tracker.sv"
`include "axi_transaction_fvip.sv"
