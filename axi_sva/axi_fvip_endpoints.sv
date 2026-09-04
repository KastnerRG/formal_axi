// Compile Manager under AXI_FVIP_MANAGER, then the default Subordinate polarity.
`define AXI_FVIP_MANAGER
`include "axi_sva/our/axi_fvip.sv"
`undef AXI_FVIP_MANAGER
`include "axi_sva/our/axi_fvip.sv"
