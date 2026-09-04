// Constant-state AXI4 normal-transaction tracking.
//
// Every checker selects one arbitrary occurrence and tracks only its bounded
// relative rank.  State grows with ID/burst widths and the logarithm of the
// configured bounds, never with the number of outstanding transactions.

module `MODNAME_READ_TRACKER #(
  parameter int ID_W = 4,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16
) (
  input logic clk,
  input logic rstn,
  input logic [ID_W-1:0] watch_id,
  input logic ar_hsk,
  input logic [ID_W-1:0] ar_id,
  input logic [7:0] ar_len,
  input logic r_valid,
  input logic r_hsk,
  input logic [ID_W-1:0] r_id,
  input logic r_last
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int COUNT_W = (MAX_OUTSTANDING < 2) ? 1 : $clog2(MAX_OUTSTANDING+1);
  localparam int AGE_W = (MAX_RESPONSE_DELAY < 2) ? 1 : $clog2(MAX_RESPONSE_DELAY+1);
  localparam int BEAT_COUNT_W = (MAX_BURST_LEN < 1) ? 1 : $clog2(MAX_BURST_LEN + 1);

  (* anyseq *) logic select_now;
  logic selected, pending, completed;
  logic [COUNT_W-1:0] outstanding, rank;
  logic [7:0] watched_len;
  logic [BEAT_COUNT_W-1:0] watched_beat;
`ifdef AXI_FVIP_MANAGER
  // Only a DUT Subordinate owns R response availability.  At a DUT Manager
  // output the deterministic Subordinate environment contract supplies the
  // universal progress assumption, so a selector-local timer would be
  // redundant state and an avoidable selector-dependent assumption.
  logic [AGE_W-1:0] rsp_age;
`endif

  wire ar_watch = ar_hsk && ar_id == watch_id;
  wire r_watch = r_valid && r_id == watch_id;
  wire r_watch_hsk = r_hsk && r_id == watch_id;
  wire r_watch_last_hsk = r_watch_hsk && r_last;
  // Invalid overflow/orphan events still fire their protocol properties, but
  // cannot corrupt the shared observer.  In particular an orphan RLAST
  // concurrent with the first AR must not consume that new request.
  wire tracked_r_last = r_watch_last_hsk && outstanding != 0;
  wire tracked_ar = ar_watch && (outstanding < MAX_OUTSTANDING || tracked_r_last);
  wire rsp_eligible = pending && rank == 0;
  wire rsp_visible = rsp_eligible && r_watch;
  wire r_stalled = r_valid && !r_hsk;

  fv_stream_occurrence_core #(.WIDTH(8), .MAX_PENDING(MAX_OUTSTANDING), .MAX_DELAY(MAX_RESPONSE_DELAY)) i_occurrence (
    .clk(clk), .rstn(rstn), .select_now(select_now),
    .s_hsk(tracked_ar), .s_data(ar_len), .m_hsk(tracked_r_last),
    .selected(selected), .pending(pending), .completed(completed),
    .watched_data(watched_len), .rank(rank), .occupancy(outstanding), .age()
  );

  s_select_request: assume property (select_now |-> tracked_ar && !selected);
  s_select_once: assume property (selected |-> !select_now);

  x_r_has_ar: `TXN_DEST property (r_watch |-> outstanding != 0);
  x_r_last_exact: `TXN_DEST property (pending && rank == 0 && r_watch |->
      r_last == (watched_beat == watched_len));

`ifdef AXI_FVIP_MANAGER
  // The role reuses this Manager-input tracker state for its selected AR.
  // A pending request is one of the watched-ID requests represented by
  // outstanding, after every request ahead of it represented by rank.  This
  // zero-state bookkeeping fact is independently proved at both inputs from
  // the response no-orphan protocol assertion; it imposes no DUT behavior.
  a_tracker_pending_rank: assert property (
    pending |-> outstanding > rank);
`endif

`ifdef AXI_FVIP_MANAGER
  // MAX_RESPONSE_DELAY bounds each DUT-owned response beat once this request
  // is the per-ID head.  Once a selected beat is visible, MAX_STALL
  // separately bounds acceptance.
  generate if (ENABLE_RESPONSE_PROGRESS) begin : g_response_progress
    x_read_response_progress: assert property (
      rsp_eligible |-> rsp_visible || rsp_age < MAX_RESPONSE_DELAY);
  end endgenerate
`endif

  c_read_request: cover property (ar_hsk);
  c_read_response: cover property (r_hsk && r_last);
  c_read_max_occupancy: cover property (outstanding == MAX_OUTSTANDING);
  c_select: cover property (select_now);
  c_select_with_rank: cover property (select_now && outstanding != 0);
  c_complete: cover property (completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      watched_beat <= '0;
`ifdef AXI_FVIP_MANAGER
      rsp_age <= '0;
`endif
    end else begin
      if (select_now) begin
        watched_beat <= '0;
`ifdef AXI_FVIP_MANAGER
        rsp_age <= '0;
`endif
      end else if (pending && rank == 0 && r_watch_hsk && !r_last &&
                   watched_beat < MAX_BURST_LEN) begin
        watched_beat <= watched_beat + 1'b1;
      end

`ifdef AXI_FVIP_MANAGER
      if (ENABLE_RESPONSE_PROGRESS) begin
        if (!rsp_eligible || rsp_visible)
          rsp_age <= '0;
        // A different response already held on the channel cannot advance
        // until its READY owner accepts it.  Do not charge that stall to
        // either an assumed environment or an asserted DUT response bound.
        else if (!r_stalled && rsp_age < MAX_RESPONSE_DELAY)
          rsp_age <= rsp_age + 1'b1;
      end
`endif
    end
  end
endmodule
