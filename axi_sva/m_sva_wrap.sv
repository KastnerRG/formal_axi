`timescale 1ns/1ps

`include "params.svh"
`define MASTER
`include "axi_sva/our/axi_fvip.sv"
`undef MASTER

module m_sva_wrap #(
  parameter int ADDR_W = `AXI_ADDR_W,
  parameter int DATA_W = `AXI_DATA_W,
  parameter int ID_W = `AXI_ID_W,
  parameter int USER_W = `AXI_USER_W,
  parameter int MAX_STALL = 8,
  parameter bit ENABLE_MAX_STALL = 1'b0,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16
) (
  input logic clk,
  input logic rst,
  AXI_BUS.Monitor axi
);
// `ifdef HAVE_ARM_AXI_SVA
//   arm_formal_wrapper #(
//     .ADDR_W(ADDR_W),
//     .DATA_W(DATA_W),
//     .ID_W(ID_W),
//     .USER_W(USER_W)
//   ) u_arm (
//     .clk(clk),
//     .rst(rst),
//     .axi(axi)
//   );
// `endif

  // yosys_questa_formal_wrapper #(
  //   .ADDR_W(ADDR_W),
  //   .DATA_W(DATA_W),
  //   .ID_W(ID_W),
  //   .USER_W(USER_W),
  //   .IS_SOURCE(1'b1)
  // ) u_yosys (
  //   .clk(clk),
  //   .rst(rst),
  //   .axi(axi)
  // );

  // ZipCPU's faxi_master checks a master agent even though the internal
  // macros are named from the slave's perspective.
  // f_axi_m_wrapper #(
  //   .ADDR_W(ADDR_W),
  //   .DATA_W(DATA_W),
  //   .ID_W(ID_W)
  // ) u_zipcpu (
  //   .clk(clk),
  //   .rst(rst),
  //   .axi(axi)
  // );

  // Deliberate stable hierarchy for users that only need endpoint checking.
  // Role aggregates instantiate the same checker and consume this interface
  // through an explicit port instead.
  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(`AXI_MAX_BURST_LEN),
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY),
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
  ) view ();

  m_axi_fvip #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .ID_W(ID_W),
    .USER_W(USER_W),
    .MAX_STALL(MAX_STALL),
    .ENABLE_MAX_STALL(ENABLE_MAX_STALL),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD),
    .MAX_W_AHEAD(MAX_W_AHEAD),
    .ENABLE_EXCLUSIVE(1'b0),
    .ENABLE_ATOP(1'b0),
    .MAX_BURST_LEN(`AXI_MAX_BURST_LEN),
    .ENABLE_TRANSACTION(`AXI_ENABLE_TRANSACTION_FVIP),
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY),
    .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS),
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
  ) u_our (
    .clk(clk), .rstn(~rst), .axi(axi), .view(view)
  );
endmodule
