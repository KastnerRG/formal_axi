`timescale 1ns/1ps

`include "params.svh"

module tb_dma_register;
  localparam int unsigned DmaIdW = 1;

  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod   (10ns),
    .RstClkCycles(5)
  ) i_clk_rst_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  AXI_LITE #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W),
    .AXI_DATA_WIDTH(`AXI_DATA_W)
  ) ctrl_port ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(DmaIdW), .AXI_USER_WIDTH(`AXI_USER_W)
  ) mem_port ();

  wrapper #(
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W), .MST_ID_W(DmaIdW)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .ctrl_port(ctrl_port), .mem_port(mem_port)
  );

`ifndef VERILATOR
  axi_fvip_txn_view_if #(
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
    .ID_W(DmaIdW), .USER_W(`AXI_USER_W),
    .MAX_BURST_LEN(`AXI_MAX_BURST_LEN)
  ) mem_view ();
  subordinate_axi_fvip #(
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
    .ID_W(DmaIdW), .USER_W(`AXI_USER_W),
    .MAX_BURST_LEN(`AXI_MAX_BURST_LEN),
    .ENABLE_TRANSACTION(`AXI_ENABLE_TRANSACTION_FVIP)
  ) i_mem_fvip (
    .clk(clk), .rstn(rst_n), .axi(mem_port), .view(mem_view)
  );
`endif

  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:32] mem_port.ar_valid && mem_port.ar_ready);
  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:32] mem_port.aw_valid && mem_port.aw_ready);
endmodule
