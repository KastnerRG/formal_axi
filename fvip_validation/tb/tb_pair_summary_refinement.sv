`timescale 1ns/1ps

// Standalone refinement harness for axi_pair_tracker's staged AW summary.
//
// This intentionally contains no DUT.  AW/W offers and READY are arbitrary,
// handshakes have their normal AXI meaning, and the W beat position uses the
// same transition as axi_channel_fvip.  Consequently, the summary assertions
// prove only an observer-state transformation and cannot depend on a crossbar
// implementation or on another protocol assertion.

`define MODNAME_PAIR_TRACKER s_axi_pair_tracker_summary_refinement
`define TXN_SOURCE assert
`include "axi_pair_tracker.sv"
`undef TXN_SOURCE
`undef MODNAME_PAIR_TRACKER

module tb_pair_summary_refinement (
  input logic clk,
  input logic rstn
);
  import pkg_axi_fvip::*;

  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;
  localparam int MAX_A_AHEAD = 8;
  localparam int MAX_B_AHEAD = 8;
  localparam int MAX_BURST_LEN = 8;
  localparam int W_BEAT_W = $clog2(MAX_BURST_LEN + 1);
  localparam int SKEW_W =
    $clog2(((MAX_A_AHEAD > MAX_B_AHEAD) ?
      MAX_A_AHEAD : MAX_B_AHEAD) + 1) + 1;

  (* anyseq *) logic aw_valid;
  (* anyseq *) logic aw_ready;
  (* anyseq *) logic [ADDR_W-1:0] aw_addr;
  (* anyseq *) logic [7:0] aw_len;
  (* anyseq *) logic [2:0] aw_size;
  (* anyseq *) logic [1:0] aw_burst;
  (* anyseq *) logic w_valid;
  (* anyseq *) logic w_ready;
  (* anyseq *) logic [DATA_W/8-1:0] w_strb;
  (* anyseq *) logic w_last;
  (* anyseq *) logic lane_probe;
  (* anyseq *) logic [W_BEAT_W-1:0] beat_probe;
  (* anyseq *) logic [W_BEAT_W-1:0] count_probe;

  logic [W_BEAT_W-1:0] current_w_beat;
  logic rstn_at_posedge = 1'b0;
  logic first_sample = 1'b1;
  logic ref_aw_valid;
  logic [ADDR_W-1:0] ref_aw_addr;
  logic [7:0] ref_aw_len;
  logic [2:0] ref_aw_size;
  logic [1:0] ref_aw_burst;

  wire aw_hsk = aw_valid && aw_ready;
  wire w_hsk = w_valid && w_ready;
  wire w_last_hsk = w_hsk && w_last;
  wire signed [SKEW_W-1:0] skew;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  // Give the observer one real reset sample, then keep reset deasserted.
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
    @(negedge clk) disable iff ($isunknown(rstn)) rstn == rstn_at_posedge);

  // Keep the address geometry inside the AXI4 legal domain when it is an
  // offer.  INCR still permits every 8-bit AWLEN here, including 255; the
  // configured MAX_BURST_LEN constrains the observer counter, not this
  // refinement's width audit.
  a_aw_size_legal: assume property (
    aw_valid |-> (1 << aw_size) <= DATA_W/8);
  a_aw_burst_legal: assume property (
    aw_valid |-> aw_burst != 2'b11);
  a_aw_fixed_len_legal: assume property (
    aw_valid && aw_burst == pkg_axi_fvip::BURST_FIXED |-> aw_len <= 8'd15);
  a_aw_wrap_len_legal: assume property (
    aw_valid && aw_burst == pkg_axi_fvip::BURST_WRAP |->
      aw_len inside {8'd1, 8'd3, 8'd7, 8'd15});

  // Match the endpoint-owned channel counter exactly.  AWLEN remains a free
  // 8-bit value so the refinement also checks the 255 -> 256 summary edge.
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn)
      current_w_beat <= '0;
    else if (w_last_hsk)
      current_w_beat <= '0;
    else if (w_hsk && current_w_beat < MAX_BURST_LEN)
      current_w_beat <= current_w_beat + 1'b1;
  end

  s_axi_pair_tracker_summary_refinement #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .MAX_A_AHEAD(MAX_A_AHEAD),
    .MAX_B_AHEAD(MAX_B_AHEAD),
    .CONFIG_MAX_A_AHEAD(MAX_A_AHEAD),
    .CONFIG_MAX_B_AHEAD(MAX_B_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_WRITE_DATA_PROGRESS(1'b0)
  ) i_tracker (
    .clk(clk),
    .rstn(rstn),
    .aw_valid(aw_valid),
    .aw_hsk(aw_hsk),
    .aw_addr(aw_addr),
    .aw_len(aw_len),
    .aw_size(aw_size),
    .aw_burst(aw_burst),
    .w_valid(w_valid),
    .w_hsk(w_hsk),
    .w_strb(w_strb),
    .w_last(w_last),
    .current_w_beat(current_w_beat),
    .skew(skew)
  );

  // Validation-only golden form of the deleted raw AW snapshot.  It follows
  // the tracker's three mutually exclusive AW capture paths, but is not part
  // of the production FVIP state.
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      ref_aw_valid <= 1'b0;
      ref_aw_addr <= '0;
      ref_aw_len <= '0;
      ref_aw_size <= '0;
      ref_aw_burst <= '0;
    end else if (i_tracker.select_aw) begin
      ref_aw_valid <= 1'b1;
      ref_aw_addr <= aw_addr;
      ref_aw_len <= aw_len;
      ref_aw_size <= aw_size;
      ref_aw_burst <= aw_burst;
    end else if (i_tracker.select_w && aw_hsk && i_tracker.skew == 0) begin
      ref_aw_valid <= 1'b1;
      ref_aw_addr <= aw_addr;
      ref_aw_len <= aw_len;
      ref_aw_size <= aw_size;
      ref_aw_burst <= aw_burst;
    end else if (i_tracker.pending_w && aw_hsk && i_tracker.rank == 0) begin
      ref_aw_valid <= 1'b1;
      ref_aw_addr <= aw_addr;
      ref_aw_len <= aw_len;
      ref_aw_size <= aw_size;
      ref_aw_burst <= aw_burst;
    end
  end

  // Primitive, acyclic refinement obligations.  Proving raw capture and
  // summary capture independently from the same live payload, followed by a
  // common freeze, avoids asking induction to expand AXI address geometry.
  a_refine_raw_capture_select_aw: assert property (
    i_tracker.select_aw |=>
      ref_aw_addr == $past(aw_addr) &&
      ref_aw_len == $past(aw_len) &&
      ref_aw_size == $past(aw_size) &&
      ref_aw_burst == $past(aw_burst));
  a_refine_raw_capture_select_w_join: assert property (
    i_tracker.select_w && aw_hsk && i_tracker.skew == 0 |=>
      ref_aw_addr == $past(aw_addr) &&
      ref_aw_len == $past(aw_len) &&
      ref_aw_size == $past(aw_size) &&
      ref_aw_burst == $past(aw_burst));
  a_refine_raw_capture_pending_w_join: assert property (
    i_tracker.pending_w && aw_hsk && i_tracker.rank == 0 |=>
      ref_aw_addr == $past(aw_addr) &&
      ref_aw_len == $past(aw_len) &&
      ref_aw_size == $past(aw_size) &&
      ref_aw_burst == $past(aw_burst));
  a_refine_raw_and_summary_freeze: assert property (
    ref_aw_valid |=>
      $stable({ref_aw_addr,
               ref_aw_len,
               ref_aw_size,
               ref_aw_burst,
               i_tracker.watched_aw_beats,
               i_tracker.watched_aw_lane_legal}));
  a_refine_reference_valid_state: assert property (
    ref_aw_valid == (i_tracker.pending_aw || i_tracker.completed));
  a_refine_reference_length_summary: assert property (
    ref_aw_valid |->
      i_tracker.watched_aw_beats == {1'b0, ref_aw_len} + 9'd1);

  // The scalar lane statistic is sufficient for either value of an arbitrary
  // WSTRB bit.  This is purely combinational and independent of tracker state.
  a_refine_lane_factorization: assert property (
    aw_valid |->
      wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len,
                       i_tracker.watch_beat, i_tracker.watch_lane,
                       lane_probe, DATA_W) ==
        (lane_probe ?
          wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len,
                           i_tracker.watch_beat, i_tracker.watch_lane,
                           1'b1, DATA_W) : 1'b1));

  // Exact arithmetic substitutions used by the final source reduction.
  // The prepended zero prevents the offer-side increment from wrapping.
  a_refine_position_algebra: assert property (
    (beat_probe <= aw_len) ==
      (beat_probe < ({1'b0, aw_len} + 9'd1)));
  a_refine_terminal_algebra: assert property (
    (beat_probe == aw_len) ==
      (({1'b0, beat_probe} + 1'b1) ==
       ({1'b0, aw_len} + 9'd1)));
  a_refine_count_algebra: assert property (
    (count_probe == ({1'b0, aw_len} + 1'b1)) ==
      (count_probe == ({1'b0, aw_len} + 9'd1)));

  c_refine_lane_zero: cover property (rstn && aw_valid && !lane_probe);
  c_refine_lane_one: cover property (rstn && aw_valid && lane_probe);
  c_refine_awlen_255: cover property (
    rstn && aw_valid && aw_burst == pkg_axi_fvip::BURST_INCR &&
    aw_len == 8'hff);
endmodule
