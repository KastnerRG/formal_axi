`timescale 1ns/1ps

`include "params.svh"

module tb_fifo #(
  parameter int unsigned AXI_FIFO_DEPTH        = 2,
  parameter bit          AXI_FIFO_FALL_THROUGH = 1'b0,
  parameter int unsigned AXI_FIFO_TRACK_DEPTH = AXI_FIFO_DEPTH,
  parameter bit          AXI_FIFO_ALLOW_BYPASS = AXI_FIFO_FALL_THROUGH,
  parameter int unsigned AXI_MAX_STALL = 8,
  parameter int unsigned AXI_MAX_OUTSTANDING = 4,
  parameter int unsigned AXI_MAX_RESPONSE_DELAY = 16,
  parameter int unsigned AXI_MAX_WRITE_DATA_DELAY = 16,
  parameter int unsigned AXI_MAX_ROLE_DELAY = 100,
  parameter bit          AXI_ENABLE_BOUNDED_ENV = 1'b1
) (
`ifdef AXI_FVIP_FORMAL
  input logic clk,
  input logic rst_n
`endif
);

`ifndef AXI_FVIP_FORMAL
  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod   (10ns),
    .RstClkCycles(5)
  ) i_clk_rst_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );
`endif

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
    .MST_ID_W(`AXI_ID_W), .USER_W(`AXI_USER_W),
    .AXI_FIFO_DEPTH(AXI_FIFO_DEPTH),
    .AXI_FIFO_FALL_THROUGH(AXI_FIFO_FALL_THROUGH)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .slv_ports(slv_ports), .mst_ports(mst_ports)
  );

`ifndef VERILATOR
  fv_axi_fifo_fvip #(
    .ADDR_W(`AXI_ADDR_W),
    .DATA_W(`AXI_DATA_W),
    .ID_W(`AXI_ID_W),
    .USER_W(`AXI_USER_W),
    .DEPTH(AXI_FIFO_TRACK_DEPTH),
    .FALL_THROUGH(AXI_FIFO_ALLOW_BYPASS),
    .MAX_STALL(AXI_MAX_STALL),
    .ENABLE_MAX_STALL(AXI_ENABLE_BOUNDED_ENV),
    .MAX_OUTSTANDING(AXI_MAX_OUTSTANDING),
    .MAX_AW_AHEAD(`AXI_MAX_AW_AHEAD),
    .MAX_W_AHEAD(`AXI_MAX_W_AHEAD),
    .MAX_BURST_LEN(`AXI_MAX_BURST_LEN),
    .ENABLE_TRANSACTION(`AXI_ENABLE_TRANSACTION_FVIP),
    .ENABLE_RESPONSE_PROGRESS(AXI_ENABLE_BOUNDED_ENV),
    .MAX_RESPONSE_DELAY(AXI_MAX_RESPONSE_DELAY),
    .ENABLE_WRITE_DATA_PROGRESS(AXI_ENABLE_BOUNDED_ENV),
    .MAX_WRITE_DATA_DELAY(AXI_MAX_WRITE_DATA_DELAY),
    .ENABLE_ROLE_PROGRESS(AXI_ENABLE_BOUNDED_ENV),
    .MAX_ROLE_DELAY(AXI_MAX_ROLE_DELAY)
  ) i_fifo_fvip (
    .clk(clk), .rstn(rst_n), .s_axi(slv_ports[0]), .m_axi(mst_ports[0])
  );
`endif

  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:16] slv_ports[0].aw_valid && slv_ports[0].aw_ready);
  cover property (@(posedge clk) disable iff (!rst_n)
    ##[1:16] mst_ports[0].r_valid && mst_ports[0].r_ready);
  cover property (@(posedge clk) disable iff (!rst_n)
    slv_ports[0].w_valid && slv_ports[0].w_ready &&
    mst_ports[0].w_valid && mst_ports[0].w_ready);
endmodule
