// Two-sided selected AW/completed-W tracker.  One arbitrary beat is sampled
// for WSTRB legality, so state is independent of outstanding count and grows
// only logarithmically with maximum burst length.
module `MODNAME_PAIR_TRACKER #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int MAX_A_AHEAD = 8,
  parameter int MAX_B_AHEAD = 8,
  parameter int CONFIG_MAX_A_AHEAD = 4,
  parameter int CONFIG_MAX_B_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16,
  localparam int SKEW_W = $clog2(((MAX_A_AHEAD > MAX_B_AHEAD) ? MAX_A_AHEAD : MAX_B_AHEAD) + 1) + 1,
  localparam int BURST_COUNT_W = (MAX_BURST_LEN < 1) ? 1 : $clog2(MAX_BURST_LEN + 1)
) (
  input logic clk,
  input logic rstn,
  input logic aw_valid,
  input logic aw_hsk,
  input logic [ADDR_W-1:0] aw_addr,
  input logic [7:0] aw_len,
  input logic [2:0] aw_size,
  input logic [1:0] aw_burst,
  input logic w_valid,
  input logic w_hsk,
  input logic [DATA_W/8-1:0] w_strb,
  input logic w_last,
  input logic [BURST_COUNT_W-1:0] current_w_beat,
  output logic signed [SKEW_W-1:0] skew
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int STRB_W = DATA_W/8;
  localparam int WATCH_LANE_W = (STRB_W < 2) ? 1 : $clog2(STRB_W);
  localparam int RANK_W = SKEW_W;
  localparam int WATCH_BEAT_W = (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN);
  localparam int AGE_W = (MAX_WRITE_DATA_DELAY < 2) ? 1 : $clog2(MAX_WRITE_DATA_DELAY+1);

  (* anyseq *) logic select_aw, select_w;
  (* anyconst *) logic [WATCH_BEAT_W-1:0] watch_beat;
  (* anyconst *) logic [WATCH_LANE_W-1:0] watch_lane;
  logic selected, pending_aw, pending_w, completed;
  logic [RANK_W-1:0] rank;
`ifndef AXI_FVIP_MANAGER
  // W availability is DUT-owned only on a DUT Manager output.  Manager-input
  // traffic is constrained universally by axi_fvip_manager_env_contract.
  logic [AGE_W-1:0] wr_data_age;
`endif

  // Sufficient statistics for every later selected-AW use.  The nine-bit
  // count represents all AXI4 burst lengths, including AWLEN=255 -> 256
  // beats; the lane bit is the geometry predicate for the arbitrary WSTRB
  // lane.  No raw AW payload is retained by this protocol observer.
  logic [8:0] watched_aw_beats;
  logic watched_aw_lane_legal;
  logic [BURST_COUNT_W-1:0] watched_w_beats;
  logic sampled_wstrb_lane;

  wire w_complete = w_hsk && w_last;
  wire [BURST_COUNT_W-1:0] current_w_beats = current_w_beat + 1'b1;
  wire live_wstrb_lane = watch_lane < STRB_W ? w_strb[watch_lane] : 1'b0;
  wire completed_wstrb_lane = current_w_beat == watch_beat ? live_wstrb_lane : sampled_wstrb_lane;
  wire [8:0] live_aw_beats = {1'b0, aw_len} + 9'd1;
  wire live_aw_lane_legal =
    wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len,
                     watch_beat, watch_lane, 1'b1, DATA_W);
  wire wr_eligible = pending_aw && rank == 0;
  wire wr_visible = wr_eligible && w_valid;

  fv_ordered_pair_core #(
    .MAX_A_AHEAD(MAX_A_AHEAD), .MAX_B_AHEAD(MAX_B_AHEAD)
  ) i_pair (
    .clk(clk), .rstn(rstn), .select_a(select_aw), .select_b(select_w),
    .a_hsk(aw_hsk), .b_hsk(w_complete), .selected(selected),
    .pending_a(pending_aw), .pending_b(pending_w), .completed(completed),
    .rank(rank), .balance(skew)
  );

  // WSTRB legality forbids asserted bits outside the legal byte lanes; it
  // does not require every legal lane to be asserted.  The package's scalar
  // predicate consumes the same legal-lane mask as the full-vector contract,
  // so an arbitrary stable lane proves the universal vector rule without a
  // stored or combinational WSTRB projection here.

  s_watch_beat_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_beat));
  c_watch_beat_range: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    watch_beat < MAX_BURST_LEN);
  s_watch_lane_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_lane));
  c_watch_lane_range: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    watch_lane < STRB_W);
  s_select_one: assume property (!(select_aw && select_w));
  s_select_aw_occurrence: assume property (select_aw |-> aw_hsk && !selected && skew >= 0);
  s_select_w_occurrence: assume property (select_w |-> w_complete && !selected && skew <= 0);
  s_select_once: assume property (selected |-> !select_aw && !select_w);

`ifdef AXI_FVIP_MANAGER
  // These constrain only an external Manager.  MAX_A/B_AHEAD below are the
  // larger internal tracking capacities allowed on a DUT output.
  c_max_aw_ahead: assume property (
    aw_valid |-> skew < CONFIG_MAX_A_AHEAD);
  c_max_w_ahead: assume property (
    w_valid && w_last |-> skew > -CONFIG_MAX_B_AHEAD);
`endif

`ifdef AXI_FVIP_MANAGER
  x_a_ahead_bound: assume property (aw_valid |-> skew < MAX_A_AHEAD);
  x_b_ahead_bound: assume property (
    w_valid && w_last |-> skew > -MAX_B_AHEAD);
`else
  x_a_ahead_bound: assert property (
    aw_hsk && !w_complete |-> skew < MAX_A_AHEAD);
  x_b_ahead_bound: assert property (
    w_complete && !aw_hsk |-> skew > -MAX_B_AHEAD);
`endif
  // Pure observer bookkeeping.  These facts introduce no state and are
  // proved from the corresponding generic skew bounds before being used to
  // decompose the selected AW/completed-W association properties below.
  a_tracker_pending_aw_rank: assert property (
    pending_aw |-> skew > $signed({1'b0, rank}));
  a_tracker_pending_w_rank: assert property (
    pending_w |-> skew < -$signed({1'b0, rank}));

`ifndef AXI_FVIP_MANAGER
  // An AW/W skew bound limits buffered bursts, but cannot force DUT-owned
  // WVALID.  Bound each required output beat once its AW is next in global W
  // order; earlier bursts have their own deadline.
  generate if (ENABLE_WRITE_DATA_PROGRESS) begin : g_write_data_progress
    x_write_data_progress: assert property (
      wr_eligible |-> wr_visible || wr_data_age < MAX_WRITE_DATA_DELAY);
  end endgenerate
`endif

  // Check an AW-first burst while its selected beat is being offered, not
  // only after WREADY permits a handshake.  On a DUT output, also check the
  // accepted prefix and the count-parity live-AW/current-W association before
  // AWREADY.  The prefix case uses the rolling arbitrary-lane sample only
  // while this ghost is fresh; the current offered beat can always use the
  // live lane directly.  Manager inputs retain selector-conditioned
  // assumptions here because the deterministic Manager contract separately
  // constrains every occurrence.
`ifdef AXI_FVIP_MANAGER
  x_wstrb_live_after_aw: `TXN_SOURCE property (
      pending_aw && rank == 0 && w_valid && current_w_beat == watch_beat |->
        (live_wstrb_lane ? watched_aw_lane_legal : 1'b1));
  x_wstrb_live_select_aw: `TXN_SOURCE property (
      select_aw && skew == 0 && w_valid && current_w_beat == watch_beat |->
        wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                         watch_lane, live_wstrb_lane, DATA_W));
`else
  x_wstrb_live_after_aw: `TXN_SOURCE property (
      pending_aw && rank == 0 &&
        (watch_beat < current_w_beat ||
         (w_valid && current_w_beat == watch_beat)) |->
        (completed_wstrb_lane ? watched_aw_lane_legal : 1'b1));
  x_wstrb_live_select_aw: `TXN_SOURCE property (
      aw_valid && skew == 0 &&
        ((!selected && watch_beat < current_w_beat) ||
         (w_valid && current_w_beat == watch_beat)) |->
        wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                         watch_lane, completed_wstrb_lane, DATA_W));
`endif

  // Reject an early or missing WLAST as soon as an AW-first beat is offered.
  // On DUT outputs, the position check remains active between W offers and
  // the count-parity case uses a live AW before AWREADY.  The retrospective
  // W-first cases remain necessary because their AW metadata arrives later.
`ifdef AXI_FVIP_MANAGER
  x_w_last_offer_after_aw: `TXN_SOURCE property (
      pending_aw && rank == 0 && w_valid |->
        w_last == (current_w_beats == watched_aw_beats));
  x_w_last_offer_select_aw: `TXN_SOURCE property (
      select_aw && skew == 0 && w_valid |->
        w_last == (current_w_beats == {1'b0, aw_len} + 1'b1));
`else
  x_w_last_offer_after_aw: `TXN_SOURCE property (
      pending_aw && rank == 0 |->
        {1'b0, current_w_beat} < watched_aw_beats &&
        (!w_valid || w_last ==
          (({1'b0, current_w_beat} + 1'b1) == watched_aw_beats)));
  x_w_last_offer_select_aw: `TXN_SOURCE property (
      aw_valid && skew == 0 |->
        current_w_beat <= aw_len &&
        (!w_valid || w_last == (current_w_beat == aw_len)));
`endif

  x_w_last_exact_after_aw: `TXN_SOURCE property (
    pending_aw && w_complete && rank == 0 |->
      current_w_beats == watched_aw_beats);
  // In the W-before-AW case, a Manager-input assumption retains the canonical
  // one-cycle post-handshake form.  A DUT-output assertion instead compares
  // the saved W count with live AWLEN immediately, including while AWREADY is
  // low; the handshake capture bridge below remains an independent helper.
`ifdef AXI_FVIP_MANAGER
  x_w_last_exact_after_w: `TXN_SOURCE property (
      pending_w && aw_hsk && rank == 0 |=>
        completed &&
        watched_w_beats == watched_aw_beats);
`else
  x_w_last_exact_after_w: `TXN_SOURCE property (
      pending_w && aw_valid && rank == 0 |->
        watched_w_beats == {1'b0, aw_len} + 1'b1);
`endif

`ifndef AXI_FVIP_MANAGER
  // Decompose the DUT-output W-before-AW check without adding observer
  // state.  A live late AW either handshakes now or is stalled.  The stalled
  // invariant is proved inductively from its entry and hold edges, so an
  // arbitrary READY-low interval cannot hide a mismatched packet length.
  wire after_w_live = pending_w && rank == 0 && aw_valid;
  wire after_w_match = watched_w_beats == live_aw_beats;
  wire after_w_stalled = after_w_live && !aw_hsk;
  // This is the irreducible same-order association leaf for a selected W
  // packet at AW/W count parity.  Keep it narrower than the production
  // offer checker so it can be proved once and transported through the
  // selected-W capture and an arbitrarily long AW stall.
  a_w_last_exact_after_w_select_w_stalled_zero: assert property (
    select_w && aw_valid && !aw_hsk && skew == 0 |->
      current_w_beats == live_aw_beats);
  // Align the same equality with the post-handshake capture facts.  The
  // enclosing FVIP's reset contract makes reset release sticky, so this is
  // cycle-for-cycle equivalent to the immediate check in every legal trace.
  a_w_last_exact_after_w_handshake_post: assert property (
    after_w_live && aw_hsk |=> $past(after_w_match));
  a_w_last_exact_after_w_stall_entry: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) |->
      after_w_match);
  a_w_last_exact_after_w_entry_origin_complete: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) |->
      $past(select_w ||
        (pending_w && rank == 1 && aw_hsk) ||
        (pending_w && rank == 0 && !aw_valid)));
  // These are the exact three non-reset origins of a newly stalled late AW.
  // Phrase each at the actual entry cycle so vacuity proves that the
  // transition, rather than merely an idle predecessor, is reachable.
  a_w_last_exact_after_w_entry_select_w: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) &&
      $past(select_w) |-> after_w_match);
  // Split selected-W creation by the prior AW channel transition.  This is
  // Boolean-exhaustive even before using aw_hsk == aw_valid && aw_ready: an
  // offered AW was stalled, an AW was consumed, or no AW was offered.
  a_w_last_exact_after_w_entry_select_w_stable: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) &&
      $past(select_w && aw_valid && !aw_hsk) |-> after_w_match);
  a_w_last_exact_after_w_entry_select_w_consumed: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) &&
      $past(select_w && aw_hsk) |-> after_w_match);
  a_w_last_exact_after_w_entry_select_w_new_aw: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) &&
      $past(select_w && !aw_hsk && !aw_valid) |-> after_w_match);
  a_w_last_exact_after_w_entry_rank_advance: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) &&
      $past(pending_w && rank == 1 && aw_hsk) |-> after_w_match);
  a_w_last_exact_after_w_entry_aw_offer: assert property (
    after_w_stalled && $past(rstn) && !$past(after_w_stalled) &&
      $past(pending_w && rank == 0 && !aw_valid) |-> after_w_match);
  a_w_last_exact_after_w_stall_hold: assert property (
    after_w_stalled && after_w_match |=>
      !after_w_stalled || after_w_match);
  a_w_last_exact_after_w_stalled: assert property (
    after_w_stalled |-> after_w_match);
`endif

  x_w_last_exact_simultaneous_aw: `TXN_SOURCE property (
    select_aw && w_complete && skew == 0 |->
      current_w_beats == {1'b0, aw_len} + 1'b1);
  x_w_last_exact_simultaneous_w: `TXN_SOURCE property (
    select_w && aw_hsk && skew == 0 |->
      current_w_beats == {1'b0, aw_len} + 1'b1);

  // Independent arbitrary beat and byte-lane choices cover every WSTRB bit
  // without generating one proof target or stored vector per beat.
  x_wstrb_after_aw: `TXN_SOURCE property (
      pending_aw && w_complete && rank == 0 &&
        watch_beat < current_w_beats |->
          (completed_wstrb_lane ? watched_aw_lane_legal : 1'b1));
`ifdef AXI_FVIP_MANAGER
  x_wstrb_after_w: `TXN_SOURCE property (pending_w && aw_hsk && rank == 0 && watch_beat < watched_w_beats |->
        wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                         watch_lane, sampled_wstrb_lane, DATA_W));
`else
  x_wstrb_after_w: `TXN_SOURCE property (pending_w && aw_valid && rank == 0 && watch_beat < watched_w_beats |->
        wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                         watch_lane, sampled_wstrb_lane, DATA_W));
`endif
  x_wstrb_simultaneous_aw: `TXN_SOURCE property (
      select_aw && w_complete && skew == 0 && watch_beat < current_w_beats |->
        wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                         watch_lane, completed_wstrb_lane, DATA_W));
  x_wstrb_simultaneous_w: `TXN_SOURCE property (
      select_w && aw_hsk && skew == 0 && watch_beat < current_w_beats |->
        wstrb_lane_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                         watch_lane, completed_wstrb_lane, DATA_W));

  // Normalize both sides of the selected pair into the registers already
  // used by the directional cases.  These sticky observer invariants reduce
  // the eight join-shape obligations to two stable post-join facts without
  // adding any state.
  a_pair_completed_exact: assert property (completed |->
      watched_w_beats == watched_aw_beats);
  a_pair_completed_wstrb: assert property (
      completed && watch_beat < watched_w_beats |->
        (sampled_wstrb_lane ? watched_aw_lane_legal : 1'b1));

  // Expose the one-bit sample transition and its selected-W freeze as
  // state-free bookkeeping lemmas for the canonical WSTRB composition.
  a_tracker_wstrb_lane_capture: assert property (
      !(pending_w || completed) && w_hsk &&
        current_w_beat == watch_beat |=>
          sampled_wstrb_lane == $past(live_wstrb_lane));
  a_tracker_wstrb_lane_frozen: assert property (
      pending_w || completed |=> $stable(sampled_wstrb_lane));
`ifndef AXI_FVIP_MANAGER
  // Only the DUT-output late-AW proof consumes this bridge.  Do not elaborate
  // duplicate input-side helper checkers for the environment polarity.
  a_tracker_w_beats_capture_select_w: assert property (
      select_w |=> watched_w_beats == $past(current_w_beats));
`endif

  // Independently expose all three address-summary capture shapes.  These
  // are the permanent zero-state bookkeeping bridges for the reduced
  // representation.
  a_tracker_aw_summary_capture_select_aw: assert property (
      select_aw |=>
        watched_aw_beats == $past(live_aw_beats) &&
        watched_aw_lane_legal == $past(live_aw_lane_legal));
  a_tracker_aw_summary_capture_select_w_join: assert property (
      select_w && aw_hsk && skew == 0 |=>
        watched_aw_beats == $past(live_aw_beats) &&
        watched_aw_lane_legal == $past(live_aw_lane_legal));
  a_tracker_aw_summary_capture_pending_w_join: assert property (
      pending_w && aw_hsk && rank == 0 |=>
        watched_aw_beats == $past(live_aw_beats) &&
        watched_aw_lane_legal == $past(live_aw_lane_legal));

  // When a completed W burst was selected before its AW, the final AW
  // handshake copies only the address-side payload; the saved W beat count
  // and arbitrary-lane sample are unchanged.  Expose that one-cycle observer
  // transition so the proven sticky completed-pair invariants can be composed
  // back into the live W-before-AW checks without adding state.
  a_tracker_after_w_capture: assert property (
      pending_w && aw_hsk && rank == 0 |=>
        completed &&
        watched_aw_beats == $past(live_aw_beats) &&
        watched_aw_lane_legal == $past(live_aw_lane_legal) &&
        watched_w_beats == $past(watched_w_beats) &&
        sampled_wstrb_lane == $past(sampled_wstrb_lane));

  c_select_a: cover property (select_aw);
  c_select_b: cover property (select_w);
  c_aw_summary_capture_select_aw: cover property (select_aw);
  c_aw_summary_capture_select_w_join: cover property (
    select_w && aw_hsk && skew == 0);
  c_aw_summary_capture_pending_w_join: cover property (
    pending_w && aw_hsk && rank == 0);
  c_w_before_aw: cover property (skew < 0);
  c_aw_before_w: cover property (skew > 0);
  c_complete: cover property (completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      watched_aw_beats <= '0;
      watched_aw_lane_legal <= 1'b0;
      watched_w_beats <= '0;
      sampled_wstrb_lane <= 1'b0;
`ifndef AXI_FVIP_MANAGER
      wr_data_age <= '0;
`endif
    end else begin
      // Before selection this rolls with the current burst.  An AW-first
      // selection keeps it rolling through older W bursts; a W-first
      // selection freezes immediately so later W traffic cannot overwrite
      // the selected completed burst.
      if (!(pending_w || completed) && w_hsk &&
          current_w_beat == watch_beat)
        sampled_wstrb_lane <= live_wstrb_lane;
      if (select_aw) begin
        watched_aw_beats <= live_aw_beats;
        watched_aw_lane_legal <= live_aw_lane_legal;
`ifndef AXI_FVIP_MANAGER
        wr_data_age <= '0;
`endif
        if (w_complete && skew == 0) begin
          watched_w_beats <= current_w_beats;
        end
      end else if (select_w) begin
        watched_w_beats <= current_w_beats;
        if (aw_hsk && skew == 0) begin
          watched_aw_beats <= live_aw_beats;
          watched_aw_lane_legal <= live_aw_lane_legal;
        end
      end else if (pending_aw && rank == 0 && w_complete) begin
        watched_w_beats <= current_w_beats;
      end else if (pending_w && rank == 0 && aw_hsk) begin
        watched_aw_beats <= live_aw_beats;
        watched_aw_lane_legal <= live_aw_lane_legal;
      end


`ifndef AXI_FVIP_MANAGER
      if (ENABLE_WRITE_DATA_PROGRESS) begin
        if (!wr_eligible || wr_visible)
          wr_data_age <= '0;
        else if (wr_data_age < MAX_WRITE_DATA_DELAY)
          wr_data_age <= wr_data_age + 1'b1;
      end
`endif
    end
  end
endmodule
