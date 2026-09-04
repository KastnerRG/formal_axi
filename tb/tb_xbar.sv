`timescale 1ns/1ps

`include "params.svh"
`include "axi/assign.svh"

module tb_xbar #(
  parameter int unsigned AXI_MAX_STALL = 8,
  parameter int unsigned AXI_MAX_OUTSTANDING = 4,
  // ZIPCPU axixbar uses LGMAXBURST=3: each Manager-facing port admits at
  // most seven outstanding requests.  While external AW is stalled, the
  // core's registered AW output and the wrapper's one-entry AW skid can hold
  // two addresses as the independent W path drains.  The locked write grant
  // prevents another input from multiplying that pipeline capacity.
  parameter int unsigned AXI_MAX_OUTPUT_OUTSTANDING = 7,
  parameter int unsigned AXI_MAX_OUTPUT_AW_AHEAD = 7,
  parameter int unsigned AXI_MAX_OUTPUT_W_AHEAD =
    (AXI_MAX_OUTSTANDING < 2) ? AXI_MAX_OUTSTANDING : 2,
  parameter int unsigned AXI_MAX_RESPONSE_DELAY = 16,
  localparam int unsigned AXI_MAX_RESPONSE_CONTENDERS =
    (2 * AXI_MAX_OUTSTANDING < AXI_MAX_OUTPUT_OUTSTANDING) ?
      2 * AXI_MAX_OUTSTANDING : AXI_MAX_OUTPUT_OUTSTANDING,
  localparam int unsigned AXI_RESPONSE_QUANTUM =
    AXI_MAX_RESPONSE_DELAY + AXI_MAX_STALL + 1,
  localparam int unsigned AXI_FORWARD_ALLOWANCE =
    AXI_MAX_RESPONSE_CONTENDERS * (AXI_MAX_STALL + 2),
  // The input bound covers the request path, every complete older response
  // burst in the head-service environment, the selected beat, and the
  // return path.  The +1 in each service quantum is the sampled-clock
  // convention for an age counter initialized to zero.
  parameter int unsigned AXI_MAX_INPUT_RESPONSE_DELAY =
    2 * AXI_FORWARD_ALLOWANCE +
      (((AXI_MAX_RESPONSE_CONTENDERS - 1) * `AXI_MAX_BURST_LEN) + 1) *
      AXI_RESPONSE_QUANTUM,
  parameter int unsigned AXI_MAX_WRITE_DATA_DELAY = 16,
  localparam int unsigned AXI_WRITE_DATA_QUANTUM =
    AXI_MAX_WRITE_DATA_DELAY + AXI_MAX_STALL + 1,
  parameter int unsigned AXI_MAX_OUTPUT_WRITE_DATA_DELAY =
    AXI_FORWARD_ALLOWANCE +
      (((AXI_MAX_OUTSTANDING - 1) * `AXI_MAX_BURST_LEN) + 1) *
      AXI_WRITE_DATA_QUANTUM,
  localparam int unsigned AXI_ROLE_READ_DELAY =
    2 * AXI_FORWARD_ALLOWANCE + AXI_MAX_RESPONSE_CONTENDERS *
      `AXI_MAX_BURST_LEN * AXI_RESPONSE_QUANTUM,
  localparam int unsigned AXI_ROLE_WRITE_DELAY =
    2 * AXI_FORWARD_ALLOWANCE + AXI_MAX_OUTSTANDING *
      `AXI_MAX_BURST_LEN * AXI_WRITE_DATA_QUANTUM +
      AXI_MAX_RESPONSE_CONTENDERS * AXI_RESPONSE_QUANTUM,
  parameter int unsigned AXI_MAX_ROLE_DELAY =
    (AXI_ROLE_READ_DELAY > AXI_ROLE_WRITE_DELAY) ?
      AXI_ROLE_READ_DELAY : AXI_ROLE_WRITE_DELAY,
  parameter bit AXI_ENABLE_BOUNDED_ENV = 1'b1,
  parameter bit AXI_ENABLE_ROLE = `AXI_ENABLE_ROLE_FVIP
) (
`ifdef AXI_FVIP_FORMAL
  input logic clk,
  input logic rst_n
`endif
);
  localparam int unsigned NumMst = 2;
  localparam int unsigned NumSlv = 2;
  localparam int unsigned SlvIdW = `AXI_ID_W + 1;
  localparam logic [`AXI_ADDR_W-1:0] Addr0Base = '0;
  localparam logic [`AXI_ADDR_W-1:0] Addr1Base = `AXI_ADDR_W'(32'h0001_0000);
  localparam logic [`AXI_ADDR_W-1:0] AddrMask = `AXI_ADDR_W'(32'hffff_0000);

`ifndef AXI_FVIP_FORMAL
  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod(10ns), .RstClkCycles(5)
  ) i_clk_rst_gen (
    .clk_o(clk), .rst_no(rst_n)
  );
`endif

`ifdef AXI_XBAR_SCALAR_ENDPOINTS
  // Keep these interfaces scalar.  Questa Formal misbinds individual
  // elements of an interface array when they cross a module boundary.
  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(`AXI_ID_W), .AXI_USER_WIDTH(`AXI_USER_W)
  ) slv0 ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(`AXI_ID_W), .AXI_USER_WIDTH(`AXI_USER_W)
  ) slv1 ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(SlvIdW), .AXI_USER_WIDTH(`AXI_USER_W)
  ) mst0 ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(SlvIdW), .AXI_USER_WIDTH(`AXI_USER_W)
  ) mst1 ();
`ifdef AXI_ZIPCPU_XBAR_SCALAR_BRIDGE
  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(`AXI_ID_W), .AXI_USER_WIDTH(`AXI_USER_W)
  ) dut_slv_ports [NumMst] ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(SlvIdW), .AXI_USER_WIDTH(`AXI_USER_W)
  ) dut_mst_ports [NumSlv] ();

  `AXI_ASSIGN(dut_slv_ports[0], slv0)
  `AXI_ASSIGN(dut_slv_ports[1], slv1)
  `AXI_ASSIGN(mst0, dut_mst_ports[0])
  `AXI_ASSIGN(mst1, dut_mst_ports[1])
`endif
`else
  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(`AXI_ID_W), .AXI_USER_WIDTH(`AXI_USER_W)
  ) slv_ports [NumMst] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(`AXI_ADDR_W), .AXI_DATA_WIDTH(`AXI_DATA_W),
    .AXI_ID_WIDTH(SlvIdW), .AXI_USER_WIDTH(`AXI_USER_W)
  ) mst_ports [NumSlv] ();
`endif

  wrapper #(
    .NUM_MST(NumMst), .NUM_SLV(NumSlv),
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
    .MST_ID_W(`AXI_ID_W), .USER_W(`AXI_USER_W)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
`ifdef AXI_ZIPCPU_XBAR_SCALAR_BRIDGE
    .slv_ports(dut_slv_ports), .mst_ports(dut_mst_ports)
`else
    .slv_ports(slv_ports), .mst_ports(mst_ports)
`endif
  );

`ifndef VERILATOR
  fv_axi_xbar_fvip #(
    .ADDR_W(`AXI_ADDR_W), .DATA_W(`AXI_DATA_W),
    .IN_ID_W(`AXI_ID_W), .OUT_ID_W(SlvIdW), .USER_W(`AXI_USER_W),
    .MAX_STALL(AXI_MAX_STALL),
    .ENABLE_INPUT_MAX_STALL(1'b0),
    .ENABLE_MAX_STALL(AXI_ENABLE_BOUNDED_ENV),
    .MAX_OUTSTANDING(AXI_MAX_OUTSTANDING),
    .MAX_AW_AHEAD(`AXI_MAX_AW_AHEAD), .MAX_W_AHEAD(`AXI_MAX_W_AHEAD),
    .MAX_OUTPUT_OUTSTANDING(AXI_MAX_OUTPUT_OUTSTANDING),
    .MAX_OUTPUT_AW_AHEAD(AXI_MAX_OUTPUT_AW_AHEAD),
    .MAX_OUTPUT_W_AHEAD(AXI_MAX_OUTPUT_W_AHEAD),
    .MAX_BURST_LEN(`AXI_MAX_BURST_LEN),
    .ENABLE_TRANSACTION(`AXI_ENABLE_TRANSACTION_FVIP),
    .ENABLE_RESPONSE_PROGRESS(AXI_ENABLE_BOUNDED_ENV),
    .MAX_RESPONSE_DELAY(AXI_MAX_RESPONSE_DELAY),
    .MAX_INPUT_RESPONSE_DELAY(AXI_MAX_INPUT_RESPONSE_DELAY),
    .ENABLE_WRITE_DATA_PROGRESS(AXI_ENABLE_BOUNDED_ENV),
    .MAX_WRITE_DATA_DELAY(AXI_MAX_WRITE_DATA_DELAY),
    .MAX_OUTPUT_WRITE_DATA_DELAY(AXI_MAX_OUTPUT_WRITE_DATA_DELAY),
    .ENABLE_ROLE(AXI_ENABLE_ROLE),
    .ENABLE_ROLE_PROGRESS(AXI_ENABLE_BOUNDED_ENV),
    .MAX_ROLE_DELAY(AXI_MAX_ROLE_DELAY),
    .ADDR0_BASE(Addr0Base), .ADDR1_BASE(Addr1Base), .ADDR_MASK(AddrMask),
    .DEFAULT_ENABLE(2'b00), .DEFAULT_DEST(2'b00),
    .PREFIX_SOURCE_ID(1'b1),
`ifdef AXI_ZIPCPU_XBAR_SCALAR_BRIDGE
    .PRESERVE_REGION(1'b0), .PRESERVE_USER(1'b0),
`endif
    .ERROR_RDATA('0)
  ) i_xbar_fvip (
    .clk(clk), .rstn(rst_n),
`ifdef AXI_XBAR_SCALAR_ENDPOINTS
    .s_axi0(slv0), .s_axi1(slv1), .m_axi0(mst0), .m_axi1(mst1)
`else
    .s_axi0(slv_ports[0]), .s_axi1(slv_ports[1]),
    .m_axi0(mst_ports[0]), .m_axi1(mst_ports[1])
`endif
  );
`endif
endmodule
