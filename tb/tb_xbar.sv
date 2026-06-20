`timescale 1ns/1ps

`include "params.svh"

module tb_xbar;
  localparam int unsigned NumMst = 2;
  localparam int unsigned NumSlv = 2;
  localparam int unsigned SlvIdW = `AXI_ID_W + $clog2(NumMst);

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
  ) slv_ports [NumMst] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(SlvIdW), .AXI_USER_WIDTH(`AXI_USER_W)
  ) mst_ports [NumSlv] ();

  wrapper #(
    .NUM_MST(NumMst), .NUM_SLV(NumSlv),
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
    .MST_ID_W(`AXI_ID_W), .USER_W(`AXI_USER_W)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .slv_ports(slv_ports), .mst_ports(mst_ports)
  );

`ifndef VERILATOR
  for (genvar i = 0; i < NumMst; i++) begin : gen_slv_fvip
    m_sva_wrap #(
      .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
      .ID_W(`AXI_ID_W), .USER_W(`AXI_USER_W)
    ) i_fvip (.clk(clk), .rst(~rst_n), .axi(slv_ports[i]));
  end

  for (genvar i = 0; i < NumSlv; i++) begin : gen_mst_fvip
    s_sva_wrap #(
      .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
      .ID_W(SlvIdW), .USER_W(`AXI_USER_W)
    ) i_fvip (.clk(clk), .rst(~rst_n), .axi(mst_ports[i]));
  end
`endif

  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:16] slv_ports[0].aw_valid && slv_ports[0].aw_ready);
  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:16] mst_ports[1].ar_valid && mst_ports[1].ar_ready);
endmodule
