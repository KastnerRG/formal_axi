// Keep the aggregate declarative: all four endpoints use one of these two
// configurations.  Macro expansion deliberately preserves the historical
// endpoint instance names consumed by focused formal targets.
`define XBAR_INPUT_VIEW(NAME) \
  axi_fvip_txn_view_if #( \
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(IN_ID_W), .USER_W(USER_W), \
    .MAX_OUTSTANDING(MAX_OUTSTANDING), \
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD), \
    .MAX_BURST_LEN(MAX_BURST_LEN), \
    .MAX_RESPONSE_DELAY(MAX_INPUT_RESPONSE_DELAY), \
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY) \
  ) NAME ();

`define XBAR_OUTPUT_VIEW(NAME) \
  axi_fvip_txn_view_if #( \
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(OUT_ID_W), .USER_W(USER_W), \
    .MAX_OUTSTANDING(MAX_OUTPUT_OUTSTANDING), \
    .MAX_AW_AHEAD(MAX_OUTPUT_AW_AHEAD), \
    .MAX_W_AHEAD(MAX_OUTPUT_W_AHEAD), \
    .MAX_BURST_LEN(MAX_BURST_LEN), \
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY), \
    .MAX_WRITE_DATA_DELAY(MAX_OUTPUT_WRITE_DATA_DELAY) \
  ) NAME ();

`define XBAR_INPUT_ENDPOINT(NAME, BUS, VIEW) \
  manager_axi_fvip #( \
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(IN_ID_W), .USER_W(USER_W), \
    .MAX_STALL(MAX_STALL), .ENABLE_MAX_STALL(1'b0), \
    .ENABLE_REQUEST_MAX_STALL(ENABLE_INPUT_MAX_STALL), \
    .ENABLE_RESPONSE_MAX_STALL(ENABLE_MAX_STALL), \
    .MAX_OUTSTANDING(MAX_OUTSTANDING), \
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD), \
    .ENABLE_EXCLUSIVE(1'b0), .ENABLE_ATOP(1'b0), \
    .MAX_BURST_LEN(MAX_BURST_LEN), .ENABLE_TRANSACTION(ENABLE_TRANSACTION), \
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS), \
    .MAX_RESPONSE_DELAY(MAX_INPUT_RESPONSE_DELAY), \
    .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS), \
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY) \
  ) NAME (.clk(clk), .rstn(rstn), .axi(BUS), .view(VIEW));

`define XBAR_OUTPUT_ENDPOINT(NAME, BUS, VIEW) \
  subordinate_axi_fvip #( \
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(OUT_ID_W), .USER_W(USER_W), \
    .MAX_STALL(MAX_STALL), .ENABLE_MAX_STALL(1'b0), \
    .ENABLE_REQUEST_MAX_STALL(ENABLE_MAX_STALL), \
    .ENABLE_RESPONSE_MAX_STALL(ENABLE_INPUT_MAX_STALL), \
    .MAX_OUTSTANDING(MAX_OUTPUT_OUTSTANDING), \
    .MAX_AW_AHEAD(MAX_OUTPUT_AW_AHEAD), \
    .MAX_W_AHEAD(MAX_OUTPUT_W_AHEAD), \
    .ENABLE_EXCLUSIVE(1'b0), .ENABLE_ATOP(1'b0), \
    .MAX_BURST_LEN(MAX_BURST_LEN), .ENABLE_TRANSACTION(ENABLE_TRANSACTION), \
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS), \
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY), \
    .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS), \
    .MAX_WRITE_DATA_DELAY(MAX_OUTPUT_WRITE_DATA_DELAY) \
  ) NAME (.clk(clk), .rstn(rstn), .axi(BUS), .view(VIEW));

// 2x2 crossbar aggregate.  Endpoint protocol checking is complete and usable
// with ENABLE_ROLE=0; the optional role checker consumes only the four public
// transaction views and contains every crossbar-specific obligation.
module fv_axi_xbar_fvip #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int IN_ID_W = 4,
  parameter int OUT_ID_W = IN_ID_W + 1,
  parameter int USER_W = 1,
  parameter int MAX_STALL = 8,
  // AXI does not require an input-facing crossbar to raise READY within a
  // fixed time.  In particular, this implementation can wait for AW before
  // accepting W.  Keep that optional performance contract distinct from the
  // downstream-environment fairness used by the role proof.
  parameter bit ENABLE_INPUT_MAX_STALL = 1'b0,
  parameter bit ENABLE_MAX_STALL = 1'b0,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  // Endpoint-local limits for each DUT Manager port.  These are explicit
  // wrapper/profile capacities, not values derived from the 2x2 route role.
  // Keeping them independent is what lets ENABLE_ROLE=0 remain a complete,
  // role-agnostic endpoint proof.
  parameter int MAX_OUTPUT_OUTSTANDING = MAX_OUTSTANDING,
  parameter int MAX_OUTPUT_AW_AHEAD = MAX_AW_AHEAD,
  parameter int MAX_OUTPUT_W_AHEAD = MAX_W_AHEAD,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_TRANSACTION = 1'b1,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  localparam int MAX_RESPONSE_CONTENDERS =
    (2 * MAX_OUTSTANDING < MAX_OUTPUT_OUTSTANDING) ?
      2 * MAX_OUTSTANDING : MAX_OUTPUT_OUTSTANDING,
  localparam int RESPONSE_QUANTUM =
    MAX_RESPONSE_DELAY + MAX_STALL + 1,
  localparam int FORWARD_ALLOWANCE =
    MAX_RESPONSE_CONTENDERS * (MAX_STALL + 2),
  // These are endpoint-local protocol-profile limits, intentionally
  // independent of MAX_ROLE_DELAY.  A crossbar input includes request
  // forwarding latency before the output Subordinate's response bound starts.
  parameter int MAX_INPUT_RESPONSE_DELAY =
    2 * FORWARD_ALLOWANCE +
      (((MAX_RESPONSE_CONTENDERS - 1) * MAX_BURST_LEN) + 1) *
      RESPONSE_QUANTUM,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16,
  localparam int WRITE_DATA_QUANTUM =
    MAX_WRITE_DATA_DELAY + MAX_STALL + 1,
  parameter int MAX_OUTPUT_WRITE_DATA_DELAY =
    FORWARD_ALLOWANCE +
      (((MAX_OUTSTANDING - 1) * MAX_BURST_LEN) + 1) *
      WRITE_DATA_QUANTUM,
  parameter bit ENABLE_ROLE = 1'b1,
  parameter bit ENABLE_ROLE_PROGRESS = 1'b0,
  localparam int ROLE_READ_DELAY =
    2 * FORWARD_ALLOWANCE + MAX_RESPONSE_CONTENDERS *
      MAX_BURST_LEN * RESPONSE_QUANTUM,
  localparam int ROLE_WRITE_DELAY =
    2 * FORWARD_ALLOWANCE + MAX_OUTSTANDING *
      MAX_BURST_LEN * WRITE_DATA_QUANTUM +
      MAX_RESPONSE_CONTENDERS * RESPONSE_QUANTUM,
  parameter int MAX_ROLE_DELAY =
    (ROLE_READ_DELAY > ROLE_WRITE_DELAY) ?
      ROLE_READ_DELAY : ROLE_WRITE_DELAY,
  parameter logic [ADDR_W-1:0] ADDR0_BASE = '0,
  parameter logic [ADDR_W-1:0] ADDR1_BASE = ADDR_W'(32'h0001_0000),
  parameter logic [ADDR_W-1:0] ADDR_MASK = ADDR_W'(32'hffff_0000),
  parameter logic [1:0] DEFAULT_ENABLE = 2'b00,
  parameter logic [1:0] DEFAULT_DEST = 2'b00,
  parameter bit PREFIX_SOURCE_ID = 1'b1,
  parameter bit PRESERVE_REGION = 1'b1,
  parameter bit PRESERVE_USER = 1'b1,
  parameter logic [DATA_W-1:0] ERROR_RDATA = DATA_W'(64'hca11_ab1e_bad_cab1e)
) (
  input logic clk,
  input logic rstn,
  AXI_BUS.Monitor s_axi0,
  AXI_BUS.Monitor s_axi1,
  AXI_BUS.Monitor m_axi0,
  AXI_BUS.Monitor m_axi1
);
  // Direct users must preserve the same layer contract as the runner: a role
  // relation is meaningful only on top of the complete transaction checker.
  a_role_requires_transaction_configuration: assert property (
    @(posedge clk) !ENABLE_ROLE || ENABLE_TRANSACTION);

  localparam int GLOBAL_WR_MAX =
    (MAX_OUTSTANDING > MAX_OUTPUT_OUTSTANDING) ?
      MAX_OUTSTANDING : MAX_OUTPUT_OUTSTANDING;
  localparam int GLOBAL_WR_SUM_W =
    (2 * GLOBAL_WR_MAX < 2) ? 1 : $clog2(2 * GLOBAL_WR_MAX + 1);

  `XBAR_INPUT_VIEW(s0_view)
  `XBAR_INPUT_VIEW(s1_view)
  `XBAR_OUTPUT_VIEW(m0_view)
  `XBAR_OUTPUT_VIEW(m1_view)

  // Cross-port proof helper, expressed only in public FVIP observer state.
  // Every forwarded output AW has already been accepted at one input, while
  // its output B is accepted no later than the matching input B.  Locally
  // rejected writes occupy only the input side between their AW and DECERR B.
  // This is a generic xbar lifecycle invariant, not a single-port AXI rule.
  wire [GLOBAL_WR_SUM_W-1:0] input_global_wr_outstanding =
    GLOBAL_WR_SUM_W'(s0_view.global_wr_outstanding) +
    GLOBAL_WR_SUM_W'(s1_view.global_wr_outstanding);
  wire [GLOBAL_WR_SUM_W-1:0] output_global_wr_outstanding =
    GLOBAL_WR_SUM_W'(m0_view.global_wr_outstanding) +
    GLOBAL_WR_SUM_W'(m1_view.global_wr_outstanding);

  a_xbar_global_write_lifecycle_conservation: assert property (
    @(posedge clk) disable iff (!rstn)
      output_global_wr_outstanding <= input_global_wr_outstanding);

  c_xbar_global_write_lifecycle_nonzero: cover property (
    @(posedge clk) disable iff (!rstn)
      output_global_wr_outstanding != 0);
  c_xbar_global_write_simultaneous_input_aw_b: cover property (
    @(posedge clk) disable iff (!rstn)
      (s0_view.live_aw_valid && s0_view.live_aw_ready &&
       s0_view.live_b_valid && s0_view.live_b_ready) ||
      (s1_view.live_aw_valid && s1_view.live_aw_ready &&
       s1_view.live_b_valid && s1_view.live_b_ready));
  c_xbar_global_write_simultaneous_output_aw_b: cover property (
    @(posedge clk) disable iff (!rstn)
      (m0_view.live_aw_valid && m0_view.live_aw_ready &&
       m0_view.live_b_valid && m0_view.live_b_ready) ||
      (m1_view.live_aw_valid && m1_view.live_aw_ready &&
       m1_view.live_b_valid && m1_view.live_b_ready));

  localparam int IN_AW_W = axi_pkg::aw_width(ADDR_W, IN_ID_W, USER_W);
  wire [ADDR_W-1:0] s0_aw_addr =
    s0_view.live_aw[IN_AW_W-IN_ID_W-1 -: ADDR_W];
  wire [ADDR_W-1:0] s1_aw_addr =
    s1_view.live_aw[IN_AW_W-IN_ID_W-1 -: ADDR_W];
  wire [1:0] s0_b_resp = s0_view.live_b[USER_W+1 -: 2];
  wire [1:0] s1_b_resp = s1_view.live_b[USER_W+1 -: 2];

  function automatic logic write_is_local_error(
    input logic [ADDR_W-1:0] addr, input int source);
    write_is_local_error =
      ((addr & ADDR_MASK) != ADDR0_BASE) &&
      ((addr & ADDR_MASK) != ADDR1_BASE) &&
      !DEFAULT_ENABLE[source];
  endfunction

  c_xbar_global_write_local_error_lifecycle: cover property (
    @(posedge clk) disable iff (!rstn)
      ((s0_view.live_aw_valid && s0_view.live_aw_ready &&
        write_is_local_error(s0_aw_addr, 0)) ||
       (s1_view.live_aw_valid && s1_view.live_aw_ready &&
        write_is_local_error(s1_aw_addr, 1)))
      ##[1:16]
      ((s0_view.live_b_valid && s0_view.live_b_ready &&
        s0_b_resp == 2'b11) ||
       (s1_view.live_b_valid && s1_view.live_b_ready &&
        s1_b_resp == 2'b11)));

  `XBAR_INPUT_ENDPOINT(i_s0_endpoint, s_axi0, s0_view)
  `XBAR_INPUT_ENDPOINT(i_s1_endpoint, s_axi1, s1_view)
  `XBAR_OUTPUT_ENDPOINT(i_m0_endpoint, m_axi0, m0_view)
  `XBAR_OUTPUT_ENDPOINT(i_m1_endpoint, m_axi1, m1_view)

  if (ENABLE_ROLE) begin : g_role
    fv_axi_xbar_role_fvip #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W),
      .IN_ID_W(IN_ID_W), .OUT_ID_W(OUT_ID_W), .USER_W(USER_W),
      .MAX_OUTSTANDING(MAX_OUTSTANDING),
      .MAX_OUTPUT_OUTSTANDING(MAX_OUTPUT_OUTSTANDING),
      .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
      .MAX_OUTPUT_AW_AHEAD(MAX_OUTPUT_AW_AHEAD),
      .MAX_OUTPUT_W_AHEAD(MAX_OUTPUT_W_AHEAD),
      .MAX_BURST_LEN(MAX_BURST_LEN),
      .ENABLE_PROGRESS(ENABLE_ROLE_PROGRESS), .MAX_DELAY(MAX_ROLE_DELAY),
      .ADDR0_BASE(ADDR0_BASE), .ADDR1_BASE(ADDR1_BASE),
      .ADDR_MASK(ADDR_MASK), .DEFAULT_ENABLE(DEFAULT_ENABLE),
      .DEFAULT_DEST(DEFAULT_DEST), .PREFIX_SOURCE_ID(PREFIX_SOURCE_ID),
      .PRESERVE_REGION(PRESERVE_REGION), .PRESERVE_USER(PRESERVE_USER),
      .ERROR_RDATA(ERROR_RDATA)
    ) i_role (
      .clk(clk), .rstn(rstn),
      .s0_view(s0_view), .s1_view(s1_view),
      .m0_view(m0_view), .m1_view(m1_view)
    );
  end
endmodule

`undef XBAR_INPUT_VIEW
`undef XBAR_OUTPUT_VIEW
`undef XBAR_INPUT_ENDPOINT
`undef XBAR_OUTPUT_ENDPOINT
