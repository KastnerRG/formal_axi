`timescale 1ns/1ps

// Standalone validation of the DUT-Manager endpoint's public AW/W pair view.
//
// There is deliberately no DUT here.  Every Manager-owned AW/W signal and
// both Subordinate-owned READY signals are symbolic.  Handshakes therefore
// have only their ordinary VALID && READY meaning.  The endpoint's universal
// environment transaction contract and all bounded-progress policies are
// disabled; inactive B/R/AR channels keep unrelated destination assumptions
// outside this proof.  The only harness assumptions establish a real,
// synchronous reset sample followed by permanent release.
module tb_c6_public_pair_view_refinement (
  input logic clk,
  input logic rstn
);
  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;
  localparam int ID_W = 3;
  localparam int USER_W = 3;
  localparam int MAX_OUTSTANDING = 3;
  localparam int MAX_AW_AHEAD = 4;
  localparam int MAX_W_AHEAD = 4;
  localparam int MAX_BURST_LEN = 8;
  localparam int STRB_W = DATA_W / 8;
  localparam int W_PAYLOAD_W = DATA_W + STRB_W + 1 + USER_W;
  localparam int W_PAYLOAD_BIT_W =
    (W_PAYLOAD_W < 2) ? 1 : $clog2(W_PAYLOAD_W);

  (* anyseq *) logic aw_valid;
  (* anyseq *) logic aw_ready;
  (* anyseq *) logic [ID_W-1:0] aw_id;
  (* anyseq *) logic [ADDR_W-1:0] aw_addr;
  (* anyseq *) logic [7:0] aw_len;
  (* anyseq *) logic [2:0] aw_size;
  (* anyseq *) logic [1:0] aw_burst;
  (* anyseq *) logic aw_lock;
  (* anyseq *) logic [3:0] aw_cache;
  (* anyseq *) logic [2:0] aw_prot;
  (* anyseq *) logic [3:0] aw_qos;
  (* anyseq *) logic [3:0] aw_region;
  (* anyseq *) logic [5:0] aw_atop;
  (* anyseq *) logic [USER_W-1:0] aw_user;

  (* anyseq *) logic w_valid;
  (* anyseq *) logic w_ready;
  (* anyseq *) logic [DATA_W-1:0] w_data;
  (* anyseq *) logic [STRB_W-1:0] w_strb;
  (* anyseq *) logic w_last;
  (* anyseq *) logic [USER_W-1:0] w_user;

  logic first_sample = 1'b1;
  logic rstn_at_posedge = 1'b0;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(ADDR_W),
    .AXI_DATA_WIDTH(DATA_W),
    .AXI_ID_WIDTH(ID_W),
    .AXI_USER_WIDTH(USER_W)
  ) axi ();

  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) view ();

  wire aw_hsk = aw_valid && aw_ready;
  wire w_hsk = w_valid && w_ready;
  wire pair_live_owner =
    (view.pair_pending_aw && view.pair_rank == 0) ||
    (view.pair_select_aw && view.pair_skew == 0);
  wire [W_PAYLOAD_W-1:0] canonical_live_w = {
    w_data, w_strb, w_last, w_user
  };

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  // Give every observer one sampled reset edge, then release reset forever.
  always_ff @(posedge clk) begin
    first_sample <= 1'b0;
    rstn_at_posedge <= rstn;
  end
  a_initial_reset: assume property (
    @(posedge clk) disable iff ($isunknown(rstn))
      first_sample |-> !rstn);
  a_reset_releases: assume property (
    @(posedge clk) disable iff ($isunknown(rstn))
      !rstn |=> rstn);
  a_reset_does_not_reassert: assume property (
    @(posedge clk) disable iff ($isunknown(rstn))
      rstn |=> rstn);
  a_reset_changes_only_at_posedge: assume property (
    @(negedge clk) disable iff ($isunknown(rstn))
      rstn == rstn_at_posedge);

  // Symbolic AW/W traffic and unconstrained backpressure.  Unrelated
  // channels are quiescent rather than modeled by a target implementation.
  always_comb begin
    axi.aw_valid = aw_valid;
    axi.aw_ready = aw_ready;
    axi.aw_id = aw_id;
    axi.aw_addr = aw_addr;
    axi.aw_len = aw_len;
    axi.aw_size = aw_size;
    axi.aw_burst = aw_burst;
    axi.aw_lock = aw_lock;
    axi.aw_cache = aw_cache;
    axi.aw_prot = aw_prot;
    axi.aw_qos = aw_qos;
    axi.aw_region = aw_region;
    axi.aw_atop = aw_atop;
    axi.aw_user = aw_user;

    axi.w_valid = w_valid;
    axi.w_ready = w_ready;
    axi.w_data = w_data;
    axi.w_strb = w_strb;
    axi.w_last = w_last;
    axi.w_user = w_user;

    axi.b_valid = 1'b0;
    axi.b_id = '0;
    axi.b_resp = '0;
    axi.b_user = '0;
    axi.b_ready = 1'b0;

    axi.ar_valid = 1'b0;
    axi.ar_id = '0;
    axi.ar_addr = '0;
    axi.ar_len = '0;
    axi.ar_size = '0;
    axi.ar_burst = 2'b01;
    axi.ar_lock = 1'b0;
    axi.ar_cache = 4'b0010;
    axi.ar_prot = '0;
    axi.ar_qos = '0;
    axi.ar_region = '0;
    axi.ar_user = '0;
    axi.ar_ready = 1'b0;

    axi.r_valid = 1'b0;
    axi.r_id = '0;
    axi.r_data = '0;
    axi.r_resp = '0;
    axi.r_last = 1'b0;
    axi.r_user = '0;
    axi.r_ready = 1'b0;
  end

  // No AXI_FVIP_MANAGER define is present in this source list, so this is the
  // DUT-output-polarity endpoint: Manager behavior is asserted, never
  // assumed.  In particular, no assumption below this instance constrains
  // AWVALID, WVALID, either payload, AWLEN, or either READY signal.
  subordinate_axi_fvip #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_STALL(2),
    .ENABLE_MAX_STALL(1'b0),
    .ENABLE_REQUEST_MAX_STALL(1'b0),
    .ENABLE_RESPONSE_MAX_STALL(1'b0),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .ENABLE_EXCLUSIVE(1'b0), .ENABLE_ATOP(1'b0),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_TRANSACTION(1'b1),
    .ENABLE_ENV_TRANSACTION_CONTRACT(1'b0),
    .ENABLE_RESPONSE_PROGRESS(1'b0),
    .ENABLE_WRITE_DATA_PROGRESS(1'b0)
  ) dut (
    .clk(clk), .rstn(rstn), .axi(axi), .view(view)
  );

  // Boundary-only duplicates of the key refinement obligations.  These use
  // public view state wherever possible, keeping the proof direction acyclic:
  // live inputs -> selected observer state -> public view.
  a_refine_live_w_packing: assert property (
    view.live_w == canonical_live_w);
  a_refine_pair_aw_capture_select_aw: assert property (
    view.pair_select_aw |=> view.pair_aw == $past(view.live_aw));
  a_refine_pair_aw_capture_select_w_join: assert property (
    view.pair_select_w && aw_hsk && view.pair_skew == 0 |=>
      view.pair_aw == $past(view.live_aw));
  a_refine_pair_aw_capture_pending_w_join: assert property (
    view.pair_pending_w && aw_hsk && view.pair_rank == 0 |=>
      view.pair_aw == $past(view.live_aw));
  a_refine_pair_w_scalar_full: assert property (
    view.pair_w_payload_available == view.wr_beat_sampled &&
    (!view.pair_w_payload_available ||
      view.pair_w_payload_bit ==
        view.wr_w[view.pair_w_payload_idx]));
  a_refine_pair_w_visible: assert property (
    view.wr_data_visible == (pair_live_owner && view.live_w_valid));
  a_refine_pair_w_complete: assert property (
    view.wr_data_burst_complete ==
      (pair_live_owner && view.live_w_valid && view.live_w_ready &&
       view.live_w[USER_W]));
  a_refine_payload_index_width_and_range: assert property (
    $bits(view.pair_w_payload_idx) == W_PAYLOAD_BIT_W &&
    view.pair_w_payload_idx < W_PAYLOAD_W);

  // Width witnesses are deliberately not protocol-profile assumptions.
  // AWLEN remains all eight bits even though this focused run uses an
  // eight-beat observer profile, and the scalar selector may choose either
  // edge of the canonical {WDATA,WSTRB,WLAST,WUSER} payload.
  c_refine_awlen_255_select_aw: cover property (
    view.pair_select_aw && aw_len == 8'hff);
  c_refine_payload_index_low: cover property (
    view.pair_w_payload_idx == 0);
  c_refine_payload_index_high: cover property (
    view.pair_w_payload_idx == W_PAYLOAD_W-1);

  // Keep lints and the generated cone explicit: these definitions are the
  // only handshake semantics supplied by the harness.
  c_refine_aw_handshake: cover property (aw_hsk);
  c_refine_w_handshake: cover property (w_hsk);
endmodule
