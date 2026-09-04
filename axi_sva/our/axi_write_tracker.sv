// Selected AW occurrence tracked through its W pairing and ordered B response.
// An arbitrary-ID scalar count rejects phantom/duplicate/wrong-ID B without a
// queue of every outstanding write.
module `MODNAME_WRITE_TRACKER #(
  parameter int ID_W = 4,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 8,
  parameter int MAX_W_AHEAD = 8,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  localparam int SKEW_W =
    $clog2(((MAX_AW_AHEAD > MAX_W_AHEAD) ?
      MAX_AW_AHEAD : MAX_W_AHEAD) + 1) + 1
) (
  input logic clk,
  input logic rstn,
  input logic [ID_W-1:0] watch_id,
  input logic aw_hsk,
  input logic [ID_W-1:0] aw_id,
  input logic w_complete,
  input logic signed [SKEW_W-1:0] skew,
  input logic b_valid,
  input logic b_hsk,
  input logic [ID_W-1:0] b_id
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  // b_rank and the single per-ID count are bounded by MAX_OUTSTANDING;
  // MAX_AW_AHEAD applies only to the separate AW/completed-W skew and must
  // not widen B-order state.  At Manager inputs b_rank counts only completed
  // same-ID predecessors.  At Manager inputs and depth greater than one,
  // count_state holds completed credit; otherwise it holds outstanding AWs.
  localparam int WRITE_CAPACITY = MAX_OUTSTANDING;
  localparam int COUNT_W = (WRITE_CAPACITY < 2) ? 1 : $clog2(WRITE_CAPACITY+1);
  localparam int PAIR_MAX = (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD;
  localparam int PAIR_W = (PAIR_MAX < 2) ? 1 : $clog2(PAIR_MAX+1);
  localparam int AGE_W = (MAX_RESPONSE_DELAY < 2) ?
    1 : $clog2(MAX_RESPONSE_DELAY+1);
  localparam int CREDIT_MAX = (MAX_AW_AHEAD > MAX_OUTSTANDING) ?
    MAX_AW_AHEAD : MAX_OUTSTANDING;
  localparam int CREDIT_W = (CREDIT_MAX < 2) ?
    1 : $clog2(CREDIT_MAX+1);
  localparam int CREDIT_EXT_W = CREDIT_W + 1;

  (* anyseq *) logic select_now;
  logic selected, pending;
  wire completed = selected && !pending;
  logic [COUNT_W-1:0] count_state, b_rank;
  wire [COUNT_W-1:0] outstanding;
  logic [PAIR_W-1:0] w_rank;
  logic w_pending;
  wire wr_data_complete = selected && !w_pending;
`ifdef MASTER
  // Only a DUT Subordinate owns B response availability.  The DUT-output
  // environment is constrained universally by its deterministic contract.
  logic [AGE_W-1:0] rsp_age;
`endif

  wire aw_watch = aw_hsk && aw_id == watch_id;
  wire b_watch = b_valid && b_id == watch_id;
  wire b_watch_hsk = b_hsk && b_id == watch_id;
  wire rsp_eligible = pending && wr_data_complete && b_rank == 0;
  wire rsp_visible = rsp_eligible && b_watch;
  wire b_stalled = b_valid && !b_hsk;

`ifdef MASTER
  // For one arbitrary ID, remember only whether each AW still awaiting its
  // completed W burst belongs to that ID.  The existing signed skew supplies
  // FIFO occupancy.  At multiple outstanding depth, count_state directly
  // stores completed credit; outstanding remains a derived semantic view.
  // No count or pointer state is duplicated.  At depth one the global skew
  // identifies the only possible outstanding AW and all tag state vanishes.
  wire [SKEW_W-1:0] positive_skew =
    skew > 0 ? $unsigned(skew) : SKEW_W'(0);
  logic [CREDIT_W-1:0] watch_unpaired;
  logic watch_credit_inc;
  wire [CREDIT_EXT_W-1:0] watch_outstanding =
    MAX_OUTSTANDING == 1 ? CREDIT_EXT_W'(count_state) :
      CREDIT_EXT_W'(count_state) + CREDIT_EXT_W'(watch_unpaired);
  wire [CREDIT_EXT_W-1:0] watch_completed_credit =
    MAX_OUTSTANDING == 1 ?
      (CREDIT_EXT_W'(count_state) > CREDIT_EXT_W'(watch_unpaired) ?
        CREDIT_EXT_W'(count_state) - CREDIT_EXT_W'(watch_unpaired) : '0) :
      CREDIT_EXT_W'(count_state);
  // Consume observer state only when this B has pre-existing completed
  // same-ID credit.  In particular, an illegal early B leaves both the
  // credit and selected-write rank intact after the first violation.
  wire count_dec = b_watch_hsk && watch_completed_credit != 0;
  wire count_inc = MAX_OUTSTANDING == 1 ? aw_watch : watch_credit_inc;
  assign outstanding = COUNT_W'(watch_outstanding);

  generate if (MAX_OUTSTANDING == 1) begin : g_single_write_credit
    always_comb begin
      watch_unpaired = skew > 0 ? CREDIT_W'(1) : '0;
      watch_credit_inc = 1'b0;
    end
  end else begin : g_per_id_write_credit
    localparam int TAG_DEPTH = (MAX_AW_AHEAD < 1) ? 1 : MAX_AW_AHEAD;
    logic [TAG_DEPTH-1:0] aw_watch_q;
    logic selected_unpaired_is_watch;
    wire tag_pop = w_complete && skew > 0;
    wire tag_push = aw_hsk &&
      (skew > 0 || (skew == 0 && !w_complete));
    wire [SKEW_W-1:0] tag_append_index =
      positive_skew - SKEW_W'(tag_pop);

    always_comb begin
      watch_unpaired = '0;
      watch_credit_inc =
        (tag_pop && aw_watch_q[0]) ||
        (aw_watch && (skew < 0 || (skew == 0 && w_complete)));
      selected_unpaired_is_watch = 1'b0;
      for (int slot = 0; slot < TAG_DEPTH; slot++) begin
        if (SKEW_W'(slot) < positive_skew && aw_watch_q[slot])
          watch_unpaired = watch_unpaired + CREDIT_W'(1);
        if (SKEW_W'(slot) < positive_skew &&
            PAIR_W'(slot) == w_rank)
          selected_unpaired_is_watch = aw_watch_q[slot];
      end
    end

    always_ff @(posedge clk or negedge rstn) begin
      if (!rstn) begin
        aw_watch_q <= '0;
      end else begin
        if (tag_pop) begin
          for (int slot = 0; slot < TAG_DEPTH-1; slot++)
            aw_watch_q[slot] <= aw_watch_q[slot+1];
          aw_watch_q[TAG_DEPTH-1] <= 1'b0;
        end
        // On a simultaneous pop/push this later assignment deliberately
        // replaces the vacated tail of the active FIFO with the new AW tag.
        if (tag_push && tag_append_index < TAG_DEPTH)
          aw_watch_q[tag_append_index] <= aw_id == watch_id;
      end
    end

    // These selected-prefix lemmas are needed only with multiple outstanding
    // writes.  At depth one the strict global-credit composition is complete,
    // and there is intentionally no per-ID tag state to support them.
    a_tracker_pending_selected_tag: assert property (
      pending && w_pending |->
        SKEW_W'(w_rank) < positive_skew && selected_unpaired_is_watch);
  end endgenerate

  // A watched W completion contributes to b_rank only when it belongs to a
  // predecessor of the selected AW.  Suppress a saturated increment exactly
  // when the completed-credit state itself suppresses it.
  wire effective_watch_credit_inc = watch_credit_inc &&
    (count_dec || count_state < WRITE_CAPACITY);
  wire rank_inc = effective_watch_credit_inc &&
    ((select_now && skew > 0) ||
      (!select_now && w_pending && w_rank != 0));
  wire rank_dec = count_dec && b_rank != 0;
`else
  wire count_inc = aw_watch;
  wire count_dec = b_watch_hsk && count_state != 0;
  wire rank_inc = 1'b0;
  wire rank_dec = count_dec && b_rank != 0;
  assign outstanding = count_state;
`endif

  s_select_request: assume property (select_now |-> aw_watch && !selected);
  s_select_once: assume property (selected |-> !select_now);

  x_no_orphan_response: `TXN_DEST property (b_watch |-> outstanding != 0);
  x_b_has_completed_write: `TXN_DEST property (
    pending && b_rank == 0 && b_watch |-> wr_data_complete);

`ifdef MASTER
  // BVALID must consume credit which existed before this sampled edge.  A
  // concurrent AW/W association therefore cannot authorize a same-cycle B;
  // it becomes visible through the observer state on the following cycle.
  x_b_has_per_id_completed_write: assert property (
    b_watch |-> watch_completed_credit != 0);

  // The role reuses this Manager-input tracker state for its selected AW.
  // These bookkeeping invariants are independently proved under the Manager
  // environment contract and impose no DUT behavior.
  a_tracker_pending_w_rank: assert property (
    w_pending |-> skew > $signed({1'b0, w_rank}));
  a_tracker_pending_data_state: assert property (
    pending |-> w_pending || wr_data_complete);
  // While the selected AW still awaits W, completed same-ID credit consists
  // exactly of its completed predecessors.
  a_tracker_pending_w_credit_rank_exact: assert property (
    w_pending |-> watch_completed_credit == CREDIT_EXT_W'(b_rank));
`endif

`ifdef MASTER
  generate if (ENABLE_RESPONSE_PROGRESS) begin : g_response_progress
    // Begin timing only after the selected completed write is the per-ID
    // response head.  Earlier same-ID writes have their own deadline.
    x_write_response_progress: assert property (
      rsp_eligible |-> rsp_visible || rsp_age < MAX_RESPONSE_DELAY);
  end endgenerate
`endif

  c_select: cover property (select_now);
  c_select_with_rank: cover property (select_now && outstanding != 0);
  c_complete: cover property (completed);
  c_b_response: cover property (b_hsk);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      count_state <= '0;
      selected <= 1'b0;
      pending <= 1'b0;
      b_rank <= '0;
      w_rank <= '0;
      w_pending <= 1'b0;
`ifdef MASTER
      rsp_age <= '0;
`endif
    end else begin
      case ({count_inc, count_dec})
        2'b10: if (count_state < WRITE_CAPACITY)
          count_state <= count_state + 1'b1;
        2'b01: count_state <= count_state - 1'b1;
        default: count_state <= count_state;
      endcase

      if (select_now) begin
        selected <= 1'b1;
        pending <= 1'b1;
`ifdef MASTER
        b_rank <= COUNT_W'(
          watch_completed_credit - CREDIT_EXT_W'(count_dec) +
            CREDIT_EXT_W'(rank_inc));
`else
        b_rank <= outstanding - COUNT_W'(count_dec);
`endif
        if (skew < 0 || (w_complete && skew == 0)) begin
`ifdef MASTER
          rsp_age <= '0;
`endif
        end else begin
          w_pending <= 1'b1;
          w_rank <= skew - (w_complete ? 1'b1 : 1'b0);
        end
      end else begin
        if (w_pending && w_complete) begin
          if (w_rank == 0) begin
            w_pending <= 1'b0;
`ifdef MASTER
            rsp_age <= '0;
`endif
          end else begin
            w_rank <= w_rank - 1'b1;
          end
        end

        // rank_dec below consumes a valid response for a predecessor.  A
        // valid response at rank zero completes the selected transaction.
        if (pending && count_dec && b_rank == 0) begin
          pending <= 1'b0;
        end

        if (pending) begin
          case ({rank_inc, rank_dec})
            2'b10: if (b_rank < WRITE_CAPACITY)
              b_rank <= b_rank + 1'b1;
            2'b01: b_rank <= b_rank - 1'b1;
            default: b_rank <= b_rank;
          endcase
        end
      end


`ifdef MASTER
      if (ENABLE_RESPONSE_PROGRESS) begin
        if (!rsp_eligible || rsp_visible)
          rsp_age <= '0;
        else if (!b_stalled && rsp_age < MAX_RESPONSE_DELAY)
          rsp_age <= rsp_age + 1'b1;
      end
`endif
    end
  end
endmodule
