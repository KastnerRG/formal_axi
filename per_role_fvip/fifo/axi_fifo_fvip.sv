// FIFO aggregate: one complete standalone checker per exposed AXI endpoint,
// plus an optional role-only relation between their public views.
module fv_axi_fifo_fvip #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int DEPTH = 2,
  parameter bit FALL_THROUGH = 1'b0,
  parameter int MAX_STALL = 8,
  parameter bit ENABLE_MAX_STALL = 1'b0,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_TRANSACTION = 1'b1,
  parameter bit ENABLE_ROLE = 1'b1,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16,
  parameter bit ENABLE_ROLE_PROGRESS = 1'b0,
  parameter int MAX_ROLE_DELAY = 100
) (
  input logic clk,
  input logic rstn,
  AXI_BUS.Monitor s_axi,
  AXI_BUS.Monitor m_axi
);
  a_role_requires_transaction_configuration: assert property (
    @(posedge clk) !ENABLE_ROLE || ENABLE_TRANSACTION);

  // The environment bounds describe behavior at the outer endpoint where it
  // is generated.  A DUT-owned event at the opposite endpoint includes both
  // FIFO crossings as well, so give that standalone endpoint checker the
  // corresponding compositional bounds.  Independent AW and W storage can
  // add at most DEPTH unmatched entries to either side of the output skew.
  localparam int COMPOSED_AW_AHEAD = MAX_AW_AHEAD + DEPTH;
  localparam int COMPOSED_W_AHEAD = MAX_W_AHEAD + DEPTH;
  localparam int COMPOSED_RESPONSE_DELAY =
    MAX_RESPONSE_DELAY + 2 * MAX_ROLE_DELAY;
  localparam int COMPOSED_WRITE_DATA_DELAY =
    MAX_WRITE_DATA_DELAY + 2 * MAX_ROLE_DELAY;

  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .MAX_RESPONSE_DELAY(COMPOSED_RESPONSE_DELAY),
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
  ) s_view ();

  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(COMPOSED_AW_AHEAD), .MAX_W_AHEAD(COMPOSED_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY),
    .MAX_WRITE_DATA_DELAY(COMPOSED_WRITE_DATA_DELAY)
  ) m_view ();

  manager_axi_fvip #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_STALL(MAX_STALL), .ENABLE_MAX_STALL(ENABLE_MAX_STALL),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .ENABLE_EXCLUSIVE(1'b0), .ENABLE_ATOP(1'b0),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_TRANSACTION(ENABLE_TRANSACTION),
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
    .MAX_RESPONSE_DELAY(COMPOSED_RESPONSE_DELAY),
    .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS),
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
  ) i_s_endpoint (
    .clk(clk), .rstn(rstn), .axi(s_axi), .view(s_view)
  );

  subordinate_axi_fvip #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_STALL(MAX_STALL), .ENABLE_MAX_STALL(ENABLE_MAX_STALL),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(COMPOSED_AW_AHEAD), .MAX_W_AHEAD(COMPOSED_W_AHEAD),
    .ENABLE_EXCLUSIVE(1'b0), .ENABLE_ATOP(1'b0),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_TRANSACTION(ENABLE_TRANSACTION),
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY),
    .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS),
    .MAX_WRITE_DATA_DELAY(COMPOSED_WRITE_DATA_DELAY)
  ) i_m_endpoint (
    .clk(clk), .rstn(rstn), .axi(m_axi), .view(m_view)
  );

  if (ENABLE_ROLE) begin : g_role
    fv_axi_fifo_role_fvip #(
      .DEPTH(DEPTH), .FALL_THROUGH(FALL_THROUGH),
      .ENABLE_PROGRESS(ENABLE_ROLE_PROGRESS), .MAX_DELAY(MAX_ROLE_DELAY)
    ) i_role (
      .clk(clk), .rstn(rstn),
      .s_view(s_view), .m_view(m_view)
    );
  end
endmodule
