`ifndef AXI_FVIP_TXN_VIEW_IF_SV
`define AXI_FVIP_TXN_VIEW_IF_SV

`include "axi/typedef.svh"

// Stable, typed boundary between one endpoint checker and a role checker.
// req/rsp are the live AXI wires.  The remaining signals describe the one
// arbitrary txn occurrence selected by each constant-state tracker.
interface axi_fvip_txn_view_if #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter int MAX_RESPONSE_DELAY = 16,
  parameter int MAX_WRITE_DATA_DELAY = 16
);
  localparam int STRB_W = DATA_W / 8;
  localparam int AW_W = ID_W + ADDR_W + 35 + USER_W;
  localparam int W_W = DATA_W + STRB_W + 1 + USER_W;
  localparam int W_PAYLOAD_BIT_W = (W_W < 2) ? 1 : $clog2(W_W);
  localparam int B_W = ID_W + 2 + USER_W;
  localparam int AR_W = ID_W + ADDR_W + 29 + USER_W;
  localparam int R_W = ID_W + DATA_W + 3 + USER_W;
  localparam int STATE_MAX = MAX_OUTSTANDING + MAX_AW_AHEAD + MAX_W_AHEAD;
  localparam int STATE_W = (STATE_MAX < 2) ? 1 : $clog2(STATE_MAX + 1);
  localparam int PAIR_MAX =
    (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD;
  localparam int PAIR_SKEW_W = $clog2(PAIR_MAX + 1) + 1;
  localparam int W_BEAT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1);
  localparam int RSP_AGE_W =
    (MAX_RESPONSE_DELAY < 2) ? 1 : $clog2(MAX_RESPONSE_DELAY + 1);
  localparam int WR_AGE_W =
    (MAX_WRITE_DATA_DELAY < 2) ? 1 : $clog2(MAX_WRITE_DATA_DELAY + 1);

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [ID_W-1:0] id_t;
  typedef logic [STRB_W-1:0] strb_t;
  typedef logic [USER_W-1:0] user_t;

  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)
  `AXI_TYPEDEF_REQ_T(req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(rsp_t, b_chan_t, r_chan_t)

  req_t req; // Live Manager-driven AXI request signals at this endpoint.
  rsp_t rsp; // Live Subordinate-driven AXI response signals at this endpoint.

  // Parameter-exact live channel boundary.  These flat channel vectors keep
  // payload and handshake signals on distinct interface objects.  Besides
  // being convenient for role FVIPs, this avoids simulator/formal-tool
  // aliasing seen when a packed req/rsp record crosses a modport hierarchy.
  logic [AW_W-1:0] live_aw;
  logic [W_W-1:0] live_w;
  logic [B_W-1:0] live_b;
  logic [AR_W-1:0] live_ar;
  logic [R_W-1:0] live_r;
  logic live_aw_valid, live_aw_ready;
  logic live_w_valid, live_w_ready;
  logic live_b_valid, live_b_ready;
  logic live_ar_valid, live_ar_ready;
  logic live_r_valid, live_r_ready;
  logic [W_BEAT_W-1:0] channel_w_beat; // Shared endpoint-owned W burst position.
  // All accepted writes still awaiting B, independent of the arbitrary-ID
  // domain below.  This is a combinational export of the endpoint observer,
  // not additional transaction state.
  logic [STATE_W-1:0] global_wr_outstanding;

  // Selected AR-to-R transaction exported for a role checker.
  logic rd_select;                          // Pulses when the tracker chooses the current AR handshake.
  logic [ID_W-1:0] rd_watch_id;            // Arbitrary same-ID domain used by the read tracker.
  logic rd_selected;                        // Stays high once an AR occurrence has been chosen.
  logic rd_pending;                         // The chosen read is still waiting for its final R beat.
  logic rd_completed;                       // The chosen read has completed; useful for reachability covers.
  logic [STATE_W-1:0] rd_rank;              // Same-ID read transactions ahead of the chosen read.
  logic [STATE_W-1:0] rd_outstanding;       // Accepted same-ID reads that have not completed.
  ar_chan_t rd_ar;                          // Captured AR payload for the chosen read.
  logic [7:0] rd_beat_idx;                  // Arbitrary beat index the role checker should observe.
  logic [7:0] rd_rsp_beat;                  // Current response-beat index within the chosen read.
  r_chan_t rd_r;                            // Captured R payload at rd_beat_idx.
  logic rd_beat_sampled;                    // rd_r contains the requested observed beat.
  logic rd_rsp_visible;                     // The next required R beat is currently VALID.
  logic rd_rsp_complete;                    // The chosen read's final R beat handshakes now.
  logic [RSP_AGE_W-1:0] rd_rsp_wait_cycles; // Cycles spent waiting for the next required R beat.

  // Selected AW-to-B transaction exported for a role checker.
  logic wr_select;                          // Pulses when the tracker chooses the current AW handshake.
  logic [ID_W-1:0] wr_watch_id;            // Arbitrary same-ID domain used by the write tracker.
  logic wr_selected;                        // Stays high once an AW occurrence has been chosen.
  logic wr_pending;                         // The chosen write is still waiting for its B response.
  logic wr_completed;                       // The chosen B response has handshaken.
  logic [STATE_W-1:0] wr_rank;              // Same-ID predecessors ahead; completed-only at Manager inputs.
  logic [STATE_W-1:0] wr_outstanding;       // Accepted same-ID writes that have not received B.
  aw_chan_t wr_aw;                          // Captured AW payload for the chosen write.
  logic wr_data_pending;                    // The chosen AW is waiting for its matching W burst.
  logic [STATE_W-1:0] wr_data_rank;         // Completed W bursts ahead of the chosen AW's burst.
  logic wr_data_complete;                   // The W burst paired with the chosen AW has completed.
  b_chan_t wr_b;                            // Captured B payload for the chosen write.
  logic wr_rsp_visible;                     // The chosen write's B response is currently VALID.
  logic wr_rsp_complete;                    // The chosen write's B response handshakes now.
  logic [RSP_AGE_W-1:0] wr_rsp_wait_cycles; // Cycles spent waiting for the chosen B response.

  // Selected AW/W association. Two selectors keep W-before-AW eligible.
  logic pair_select_aw;                     // Pulses when association tracking starts from AW.
  logic pair_select_w;                      // Pulses when association tracking starts from completed W.
  logic pair_selected;                      // Stays high once either side of a pair is chosen.
  logic pair_pending_aw;                    // A chosen AW is waiting for its matching W burst.
  logic pair_pending_w;                     // A chosen W burst is waiting for its matching AW.
  logic pair_completed;                     // The chosen AW and W burst have been paired.
  logic [STATE_W-1:0] pair_rank;            // Opposite-side bursts ahead of the required match.
  logic signed [PAIR_SKEW_W-1:0] pair_skew; // All accepted AWs minus all completed W bursts.
  aw_chan_t pair_aw;                        // Captured AW payload for the matched pair.
  logic [7:0] wr_beat_idx;                  // Arbitrary W beat index the role checker should observe.
  w_chan_t wr_w;                            // Captured W payload at wr_beat_idx.
  logic wr_beat_sampled;                    // wr_w contains the requested observed beat.
  logic [W_PAYLOAD_BIT_W-1:0] pair_w_payload_idx; // Independent arbitrary canonical-W payload bit.
  logic pair_w_payload_bit;                 // Scalar shadow of wr_w[pair_w_payload_idx].
  logic pair_w_payload_available;           // Scalar shadow contains the selected beat.
  logic wr_data_visible;                    // The next required W beat is currently VALID.
  logic wr_data_burst_complete;             // The matching WLAST handshakes now.
  logic [WR_AGE_W-1:0] wr_data_wait_cycles; // Cycles spent waiting for the next required W beat.

  modport Producer (
    output req, rsp,
    output live_aw, live_w, live_b, live_ar, live_r,
      channel_w_beat,
      live_aw_valid, live_aw_ready, live_w_valid, live_w_ready,
      live_b_valid, live_b_ready, live_ar_valid, live_ar_ready,
      live_r_valid, live_r_ready, global_wr_outstanding,
    output rd_select, rd_watch_id, rd_selected, rd_pending, rd_completed,
      rd_rank, rd_outstanding, rd_ar, rd_beat_idx,
      rd_rsp_beat, rd_r, rd_beat_sampled,
      rd_rsp_visible, rd_rsp_complete, rd_rsp_wait_cycles,
    output wr_select, wr_watch_id, wr_selected, wr_pending, wr_completed,
      wr_rank, wr_outstanding, wr_aw, wr_data_pending, wr_data_rank,
      wr_data_complete, wr_b,
      wr_rsp_visible, wr_rsp_complete, wr_rsp_wait_cycles,
    output pair_select_aw, pair_select_w, pair_selected, pair_pending_aw,
      pair_pending_w, pair_completed, pair_rank, pair_skew, pair_aw, wr_beat_idx,
      wr_w, wr_beat_sampled, pair_w_payload_idx, pair_w_payload_bit,
      pair_w_payload_available, wr_data_visible,
      wr_data_burst_complete, wr_data_wait_cycles
  );

  modport Consumer (
    input req, rsp,
    input live_aw, live_w, live_b, live_ar, live_r,
      channel_w_beat,
      live_aw_valid, live_aw_ready, live_w_valid, live_w_ready,
      live_b_valid, live_b_ready, live_ar_valid, live_ar_ready,
      live_r_valid, live_r_ready, global_wr_outstanding,
    input rd_select, rd_watch_id, rd_selected, rd_pending, rd_completed,
      rd_rank, rd_outstanding, rd_ar, rd_beat_idx,
      rd_rsp_beat, rd_r, rd_beat_sampled,
      rd_rsp_visible, rd_rsp_complete, rd_rsp_wait_cycles,
    input wr_select, wr_watch_id, wr_selected, wr_pending, wr_completed,
      wr_rank, wr_outstanding, wr_aw, wr_data_pending, wr_data_rank,
      wr_data_complete, wr_b,
      wr_rsp_visible, wr_rsp_complete, wr_rsp_wait_cycles,
    input pair_select_aw, pair_select_w, pair_selected, pair_pending_aw,
      pair_pending_w, pair_completed, pair_rank, pair_skew, pair_aw, wr_beat_idx,
      wr_w, wr_beat_sampled, pair_w_payload_idx, pair_w_payload_bit,
      pair_w_payload_available, wr_data_visible,
      wr_data_burst_complete, wr_data_wait_cycles
  );
endinterface

`endif
