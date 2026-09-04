`ifndef AXI_FVIP_TXN_VIEW_IF_SV
`define AXI_FVIP_TXN_VIEW_IF_SV

`include "axi/typedef.svh"

// Stable, typed boundary between one endpoint checker and a role checker.
// live_* carry the AXI channel wires; the flat lifecycle fields describe the
// arbitrary transaction occurrence selected by each constant-state tracker.
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
  localparam int AW_W = axi_pkg::aw_width(ADDR_W, ID_W, USER_W);
  localparam int W_W = axi_pkg::w_width(DATA_W, USER_W);
  localparam int W_PAYLOAD_BIT_W = (W_W < 2) ? 1 : $clog2(W_W);
  localparam int B_W = axi_pkg::b_width(ID_W, USER_W);
  localparam int AR_W = axi_pkg::ar_width(ADDR_W, ID_W, USER_W);
  localparam int R_W = axi_pkg::r_width(DATA_W, ID_W, USER_W);
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
  // Parameter-exact live channel boundary. These flat channel vectors keep
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

  // Keep parameter-dependent observations as separate interface objects.
  // Questa Formal 2023.2 caches packed-typedef member offsets across
  // differently parameterized interface instances, so a packed aggregate is
  // not a sound transport when input and output ID widths differ.
  logic rd_select;
  id_t rd_watch_id;
  logic rd_selected, rd_pending, rd_completed;
  logic [STATE_W-1:0] rd_rank, rd_outstanding;
  ar_chan_t rd_ar;
  logic [7:0] rd_beat_idx, rd_rsp_beat;
  r_chan_t rd_r;
  logic rd_beat_sampled, rd_rsp_visible, rd_rsp_complete;
  logic [RSP_AGE_W-1:0] rd_rsp_wait_cycles;

  logic wr_select;
  id_t wr_watch_id;
  logic wr_selected, wr_pending, wr_completed;
  logic [STATE_W-1:0] wr_rank, wr_outstanding;
  aw_chan_t wr_aw;
  logic wr_data_pending;
  logic [STATE_W-1:0] wr_data_rank;
  logic wr_data_complete;
  b_chan_t wr_b;
  logic wr_rsp_visible, wr_rsp_complete;
  logic [RSP_AGE_W-1:0] wr_rsp_wait_cycles;

  logic pair_select_aw, pair_select_w, pair_selected;
  logic pair_pending_aw, pair_pending_w, pair_completed;
  logic [STATE_W-1:0] pair_rank;
  logic signed [PAIR_SKEW_W-1:0] pair_skew;
  aw_chan_t pair_aw;
  logic [7:0] wr_beat_idx;
  w_chan_t wr_w;
  logic wr_beat_sampled;
  logic [W_PAYLOAD_BIT_W-1:0] pair_w_payload_idx;
  logic pair_w_payload_bit, pair_w_payload_available;
  logic wr_data_visible, wr_data_burst_complete;
  logic [WR_AGE_W-1:0] wr_data_wait_cycles;

  modport Producer (
    output live_aw, live_w, live_b, live_ar, live_r,
      channel_w_beat,
      live_aw_valid, live_aw_ready, live_w_valid, live_w_ready,
      live_b_valid, live_b_ready, live_ar_valid, live_ar_ready,
      live_r_valid, live_r_ready, global_wr_outstanding,
    output rd_select, rd_watch_id, rd_selected, rd_pending, rd_completed,
      rd_rank, rd_outstanding, rd_ar, rd_beat_idx, rd_rsp_beat, rd_r,
      rd_beat_sampled, rd_rsp_visible, rd_rsp_complete, rd_rsp_wait_cycles,
    output wr_select, wr_watch_id, wr_selected, wr_pending, wr_completed,
      wr_rank, wr_outstanding, wr_aw, wr_data_pending, wr_data_rank,
      wr_data_complete, wr_b, wr_rsp_visible, wr_rsp_complete,
      wr_rsp_wait_cycles,
    output pair_select_aw, pair_select_w, pair_selected, pair_pending_aw,
      pair_pending_w, pair_completed, pair_rank, pair_skew, pair_aw,
      wr_beat_idx, wr_w, wr_beat_sampled, pair_w_payload_idx,
      pair_w_payload_bit, pair_w_payload_available, wr_data_visible,
      wr_data_burst_complete, wr_data_wait_cycles
  );

  modport Consumer (
    input live_aw, live_w, live_b, live_ar, live_r,
      channel_w_beat,
      live_aw_valid, live_aw_ready, live_w_valid, live_w_ready,
      live_b_valid, live_b_ready, live_ar_valid, live_ar_ready,
      live_r_valid, live_r_ready, global_wr_outstanding,
    input rd_select, rd_watch_id, rd_selected, rd_pending, rd_completed,
      rd_rank, rd_outstanding, rd_ar, rd_beat_idx, rd_rsp_beat, rd_r,
      rd_beat_sampled, rd_rsp_visible, rd_rsp_complete, rd_rsp_wait_cycles,
    input wr_select, wr_watch_id, wr_selected, wr_pending, wr_completed,
      wr_rank, wr_outstanding, wr_aw, wr_data_pending, wr_data_rank,
      wr_data_complete, wr_b, wr_rsp_visible, wr_rsp_complete,
      wr_rsp_wait_cycles,
    input pair_select_aw, pair_select_w, pair_selected, pair_pending_aw,
      pair_pending_w, pair_completed, pair_rank, pair_skew, pair_aw,
      wr_beat_idx, wr_w, wr_beat_sampled, pair_w_payload_idx,
      pair_w_payload_bit, pair_w_payload_available, wr_data_visible,
      wr_data_burst_complete, wr_data_wait_cycles
  );
endinterface

`endif
