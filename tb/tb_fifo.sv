`timescale 1ns/1ps

`include "params.svh"

module tb_fifo;
  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod   (10ns),
    .RstClkCycles(5)
  ) i_clk_rst_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(`AXI_ID_W), .AXI_USER_WIDTH(`AXI_USER_W)
  ) slv_ports [1] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(`AXI_ID_W), .AXI_USER_WIDTH(`AXI_USER_W)
  ) mst_ports [1] ();

  wrapper #(
    .NUM_MST(1), .NUM_SLV(1),
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
    .MST_ID_W(`AXI_ID_W), .USER_W(`AXI_USER_W)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .slv_ports(slv_ports), .mst_ports(mst_ports)
  );

`ifndef VERILATOR
  m_sva_wrap i_slv_fvip (.clk(clk), .rst(~rst_n), .axi(slv_ports[0]));
  s_sva_wrap i_mst_fvip (.clk(clk), .rst(~rst_n), .axi(mst_ports[0]));
`endif

  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:16] slv_ports[0].aw_valid && slv_ports[0].aw_ready);
  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:16] mst_ports[0].r_valid && mst_ports[0].r_ready);
endmodule
