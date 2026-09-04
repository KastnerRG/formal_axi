`include "axi/typedef.svh"

// End-to-end selected write transaction for one arbitrarily chosen crossbar
// source port.
// Tracks AW routing, W ownership through WLAST, and B return.  An arbitrary W
// beat proves payload preservation without storing complete bursts.
module fv_xbar_write_tracker #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int IN_ID_W = 4,
  parameter int OUT_ID_W = IN_ID_W + 1,
  parameter int USER_W = 1,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_OUTPUT_OUTSTANDING = MAX_OUTSTANDING,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter int MAX_OUTPUT_AW_AHEAD = MAX_AW_AHEAD,
  parameter int MAX_OUTPUT_W_AHEAD = MAX_W_AHEAD,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 32,
  parameter logic [ADDR_W-1:0] ADDR0_BASE = '0,
  parameter logic [ADDR_W-1:0] ADDR1_BASE = ADDR_W'(32'h0001_0000),
  parameter logic [ADDR_W-1:0] ADDR_MASK = ADDR_W'(32'hffff_0000),
  parameter logic [1:0] DEFAULT_ENABLE = 2'b00,
  parameter logic [1:0] DEFAULT_DEST = 2'b00,
  parameter bit PRESERVE_USER = 1'b1,
  parameter int PAYLOAD_BIT_W = 1,
  localparam int WATCH_W = (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN),
  localparam int IN_W_W = DATA_W + DATA_W/8 + 1 + USER_W,
  localparam int IN_PAIR_MAX =
    (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD,
  localparam int IN_PAIR_SKEW_W = $clog2(IN_PAIR_MAX + 1) + 1,
  localparam int OUT_PAIR_MAX =
    (MAX_OUTPUT_AW_AHEAD > MAX_OUTPUT_W_AHEAD) ?
      MAX_OUTPUT_AW_AHEAD : MAX_OUTPUT_W_AHEAD,
  localparam int OUT_PAIR_SKEW_W = $clog2(OUT_PAIR_MAX + 1) + 1,
  localparam int IN_STATE_MAX =
    MAX_OUTSTANDING + MAX_AW_AHEAD + MAX_W_AHEAD,
  localparam int IN_STATE_W =
    (IN_STATE_MAX < 2) ? 1 : $clog2(IN_STATE_MAX + 1),
  localparam int OUT_STATE_MAX =
    MAX_OUTPUT_OUTSTANDING + MAX_OUTPUT_AW_AHEAD + MAX_OUTPUT_W_AHEAD,
  localparam int OUT_STATE_W =
    (OUT_STATE_MAX < 2) ? 1 : $clog2(OUT_STATE_MAX + 1),
  localparam int W_BEAT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1),
  localparam int W_PAYLOAD_BIT_W = (IN_W_W < 2) ? 1 : $clog2(IN_W_W)
) (
  input logic clk,
  input logic rstn,
  input logic enable,
  input logic source,
  input logic [1:0] watch_route,
  input logic [PAYLOAD_BIT_W-1:0] watch_payload_bit,
  input logic role_selected,
  input logic select_now,
  input logic route_hsk,
  input logic route_offer,
  input logic route_pending,
  input logic route_completed,
  axi_fvip_txn_view_if.Consumer s0_view,
  axi_fvip_txn_view_if.Consumer s1_view,
  axi_fvip_txn_view_if.Consumer m0_view,
  axi_fvip_txn_view_if.Consumer m1_view
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam logic [1:0] DEST_ERROR = 2'd2;
  localparam int MST_MAX = 2 * MAX_OUTSTANDING;
  localparam int MST_COUNT_W = (MST_MAX < 2) ? 1 : $clog2(MST_MAX + 1);
  localparam int PAIR_COUNT_W =
    (MAX_AW_AHEAD < 2) ? 1 : $clog2(MAX_AW_AHEAD + 1);
  localparam int MST_AW_MAX = MAX_OUTPUT_AW_AHEAD;
  localparam int MST_AW_COUNT_W =
    (MST_AW_MAX < 2) ? 1 : $clog2(MST_AW_MAX + 1);
  localparam int MST_W_AHEAD = MAX_OUTPUT_W_AHEAD;
  localparam int MST_WQ_DEPTH = (MST_W_AHEAD < 1) ? 1 : MST_W_AHEAD;
  localparam int MST_WQ_COUNT_W =
    (MST_W_AHEAD < 2) ? 1 : $clog2(MST_W_AHEAD + 1);
  localparam int WQ_DEPTH = (MAX_W_AHEAD < 1) ? 1 : MAX_W_AHEAD;
  localparam int WQ_COUNT_W =
    (MAX_W_AHEAD < 2) ? 1 : $clog2(MAX_W_AHEAD + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);
  localparam int W_CANON_W = axi_pkg::w_width(DATA_W, USER_W);
  localparam int B_CANON_W = axi_pkg::b_width(IN_ID_W, USER_W);
  localparam int OUT_B_W = axi_pkg::b_width(OUT_ID_W, USER_W);

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [DATA_W/8-1:0] strb_t;
  typedef logic [USER_W-1:0] user_t;
  typedef logic [IN_ID_W-1:0] in_id_t;
  typedef logic [OUT_ID_W-1:0] out_id_t;
  `AXI_TYPEDEF_AW_CHAN_T(in_aw_t, addr_t, in_id_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(in_w_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(in_b_t, in_id_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(out_w_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(out_b_t, out_id_t, user_t)

  // Select only the three channels this tracker consumes. Payload and
  // handshake signals remain separate across the public-view boundary.
  in_aw_t s_aw;
  in_w_t s_w;
  in_b_t s_b;
  out_w_t m_w [2];
  out_b_t m_b [2];
  assign s_aw = source ? s1_view.live_aw : s0_view.live_aw;
  assign s_w = source ? s1_view.live_w : s0_view.live_w;
  assign s_b = source ? s1_view.live_b : s0_view.live_b;
  assign m_w[0] = m0_view.live_w;
  assign m_w[1] = m1_view.live_w;
  assign m_b[0] = m0_view.live_b;
  assign m_b[1] = m1_view.live_b;

  wire s_aw_valid = source ? s1_view.live_aw_valid : s0_view.live_aw_valid;
  wire s_aw_ready = source ? s1_view.live_aw_ready : s0_view.live_aw_ready;
  wire s_w_valid = source ? s1_view.live_w_valid : s0_view.live_w_valid;
  wire s_w_ready = source ? s1_view.live_w_ready : s0_view.live_w_ready;
  wire s_b_valid = source ? s1_view.live_b_valid : s0_view.live_b_valid;
  wire s_b_ready = source ? s1_view.live_b_ready : s0_view.live_b_ready;
  wire [1:0] m_aw_valid = {m1_view.live_aw_valid, m0_view.live_aw_valid};
  wire [1:0] m_aw_ready = {m1_view.live_aw_ready, m0_view.live_aw_ready};
  wire [1:0] m_w_valid = {m1_view.live_w_valid, m0_view.live_w_valid};
  wire [1:0] m_w_ready = {m1_view.live_w_ready, m0_view.live_w_ready};
  wire [1:0] m_b_valid = {m1_view.live_b_valid, m0_view.live_b_valid};
  wire [1:0] m_b_ready = {m1_view.live_b_ready, m0_view.live_b_ready};

  // Endpoint observations stay locally named so the property and state
  // machinery below remains a literal use of the established proof model.
  wire [IN_ID_W-1:0] watch_id =
    source ? s1_view.wr_watch_id : s0_view.wr_watch_id;
  wire [WATCH_W-1:0] watch_beat = source ?
    s1_view.wr_beat_idx[WATCH_W-1:0] :
    s0_view.wr_beat_idx[WATCH_W-1:0];
  wire s_protocol_pending =
    source ? s1_view.wr_pending : s0_view.wr_pending;
  wire s_protocol_completed =
    source ? s1_view.wr_completed : s0_view.wr_completed;
  wire [IN_STATE_W-1:0] s_protocol_rank =
    source ? s1_view.wr_rank : s0_view.wr_rank;
  wire s_protocol_w_pending =
    source ? s1_view.wr_data_pending : s0_view.wr_data_pending;
  wire [IN_STATE_W-1:0] s_protocol_w_rank =
    source ? s1_view.wr_data_rank : s0_view.wr_data_rank;
  wire s_protocol_w_complete =
    source ? s1_view.wr_data_complete : s0_view.wr_data_complete;
  wire s_protocol_rsp_visible =
    source ? s1_view.wr_rsp_visible : s0_view.wr_rsp_visible;

  // Preserve the old route==DEST_ERROR behavior exactly: outstanding and
  // pair observations fall back to m0, while selected write-response state
  // is explicitly zero outside the two mapped routes.
  wire [OUT_STATE_W-1:0] m_protocol_outstanding = watch_route == 1 ?
    m1_view.wr_outstanding : m0_view.wr_outstanding;
  wire m_protocol_wr_select = watch_route == 1 ? m1_view.wr_select :
    (watch_route == 0 ? m0_view.wr_select : 1'b0);
  wire m_protocol_wr_selected = watch_route == 1 ? m1_view.wr_selected :
    (watch_route == 0 ? m0_view.wr_selected : 1'b0);
  wire m_protocol_wr_completed = watch_route == 1 ? m1_view.wr_completed :
    (watch_route == 0 ? m0_view.wr_completed : 1'b0);
  wire m_protocol_wr_rsp_visible = watch_route == 1 ?
    m1_view.wr_rsp_visible :
    (watch_route == 0 ? m0_view.wr_rsp_visible : 1'b0);
  wire [OUT_B_W-1:0] m_protocol_wr_b_bits = watch_route == 1 ?
    {m1_view.wr_b.id, m1_view.wr_b.resp, m1_view.wr_b.user} :
    (watch_route == 0 ?
      {m0_view.wr_b.id, m0_view.wr_b.resp, m0_view.wr_b.user} : '0);

  wire signed [IN_PAIR_SKEW_W-1:0] s_pair_skew =
    source ? s1_view.pair_skew : s0_view.pair_skew;
  wire signed [OUT_PAIR_SKEW_W-1:0] m0_pair_skew = m0_view.pair_skew;
  wire signed [OUT_PAIR_SKEW_W-1:0] m1_pair_skew = m1_view.pair_skew;
  wire s_pair_select_aw =
    source ? s1_view.pair_select_aw : s0_view.pair_select_aw;
  wire s_pair_pending_aw =
    source ? s1_view.pair_pending_aw : s0_view.pair_pending_aw;
  wire s_pair_pending_w =
    source ? s1_view.pair_pending_w : s0_view.pair_pending_w;
  wire s_pair_completed =
    source ? s1_view.pair_completed : s0_view.pair_completed;
  wire [IN_STATE_W-1:0] s_pair_rank =
    source ? s1_view.pair_rank : s0_view.pair_rank;
  wire [W_PAYLOAD_BIT_W-1:0] s_pair_w_payload_idx =
    source ? s1_view.pair_w_payload_idx : s0_view.pair_w_payload_idx;
  wire s_pair_w_payload_bit =
    source ? s1_view.pair_w_payload_bit : s0_view.pair_w_payload_bit;
  wire s_pair_w_payload_available = source ?
    s1_view.pair_w_payload_available : s0_view.pair_w_payload_available;

  wire m_pair_select_aw = watch_route == 1 ?
    m1_view.pair_select_aw : m0_view.pair_select_aw;
  wire m_pair_select_w = watch_route == 1 ?
    m1_view.pair_select_w : m0_view.pair_select_w;
  wire m_pair_pending_aw = watch_route == 1 ?
    m1_view.pair_pending_aw : m0_view.pair_pending_aw;
  wire m_pair_pending_w = watch_route == 1 ?
    m1_view.pair_pending_w : m0_view.pair_pending_w;
  wire m_pair_completed = watch_route == 1 ?
    m1_view.pair_completed : m0_view.pair_completed;
  wire [OUT_STATE_W-1:0] m_pair_rank = watch_route == 1 ?
    m1_view.pair_rank : m0_view.pair_rank;
  wire [7:0] m_pair_watch_beat = watch_route == 1 ?
    m1_view.wr_beat_idx : m0_view.wr_beat_idx;
  wire [W_PAYLOAD_BIT_W-1:0] m_pair_w_payload_idx = watch_route == 1 ?
    m1_view.pair_w_payload_idx : m0_view.pair_w_payload_idx;
  wire m_pair_w_payload_bit = watch_route == 1 ?
    m1_view.pair_w_payload_bit : m0_view.pair_w_payload_bit;
  wire m_pair_w_payload_available = watch_route == 1 ?
    m1_view.pair_w_payload_available : m0_view.pair_w_payload_available;

  wire [W_BEAT_W-1:0] s_channel_w_beat = source ?
    s1_view.channel_w_beat : s0_view.channel_w_beat;
  wire [W_BEAT_W-1:0] m0_channel_w_beat = m0_view.channel_w_beat;
  wire [W_BEAT_W-1:0] m1_channel_w_beat = m1_view.channel_w_beat;

  function automatic logic [1:0] decode(input logic [ADDR_W-1:0] addr);
    if ((addr & ADDR_MASK) == ADDR0_BASE)
      decode = 2'd0;
    else if ((addr & ADDR_MASK) == ADDR1_BASE)
      decode = 2'd1;
    else if (DEFAULT_ENABLE[source])
      decode = DEFAULT_DEST[source] ? 2'd1 : 2'd0;
    else
      decode = DEST_ERROR;
  endfunction

  wire s_aw_hsk = enable && s_aw_valid && s_aw_ready;
  wire s_w_hsk = enable && s_w_valid && s_w_ready;
  wire s_w_last = s_w_hsk && s_w.last;
  wire [1:0] s_route = decode(s_aw.addr);

  wire [1:0] m_aw_hsk, m_b_offer, m_b_watch;
  wire [1:0] m_w_hsk, m_w_last;
  wire [W_CANON_W-1:0] m_w_data [2];
  wire [B_CANON_W-1:0] m_b_data [2];
  assign m_aw_hsk[0] = enable && m_aw_valid[0] && m_aw_ready[0];
  assign m_aw_hsk[1] = enable && m_aw_valid[1] && m_aw_ready[1];
  assign m_b_offer[0] = enable && m_b_valid[0] &&
    m_b[0].id[OUT_ID_W-1] == source &&
    m_b[0].id[IN_ID_W-1:0] == watch_id;
  assign m_b_offer[1] = enable && m_b_valid[1] &&
    m_b[1].id[OUT_ID_W-1] == source &&
    m_b[1].id[IN_ID_W-1:0] == watch_id;
  assign m_b_watch[0] = m_b_offer[0] && m_b_ready[0];
  assign m_b_watch[1] = m_b_offer[1] && m_b_ready[1];
  assign m_w_hsk[0] = enable && m_w_valid[0] && m_w_ready[0];
  assign m_w_hsk[1] = enable && m_w_valid[1] && m_w_ready[1];
  assign m_w_last[0] = m_w_hsk[0] && m_w[0].last;
  assign m_w_last[1] = m_w_hsk[1] && m_w[1].last;
  assign m_w_data[0] = {
    m_w[0].data, m_w[0].strb,
    m_w[0].last, (PRESERVE_USER ? m_w[0].user : '0)
  };
  assign m_w_data[1] = {
    m_w[1].data, m_w[1].strb,
    m_w[1].last, (PRESERVE_USER ? m_w[1].user : '0)
  };
  assign m_b_data[0] = {
    m_b[0].id[IN_ID_W-1:0], m_b[0].resp,
    (PRESERVE_USER ? m_b[0].user : '0)
  };
  assign m_b_data[1] = {
    m_b[1].id[IN_ID_W-1:0], m_b[1].resp,
    (PRESERVE_USER ? m_b[1].user : '0)
  };

  logic routed;

  logic [MST_COUNT_W-1:0] m_b_rank;
  logic m_b_pending, m_b_sampled;
  logic selected_m_b_data;

  logic s_current_w_sampled;
  logic s_current_w_data;
  logic s_w_ahead_sampled [WQ_DEPTH];
  logic s_w_ahead_data [WQ_DEPTH];
  logic s_w_sampled;
  logic selected_s_w_data;

  logic m_current_w_sampled [2];
  logic m_current_w_data [2];
  logic m_w_ahead_sampled [2][MST_WQ_DEPTH];
  logic m_w_ahead_data [2][MST_WQ_DEPTH];
  logic [MST_AW_COUNT_W-1:0] m_w_rank;
  logic selected_m_w_pending, selected_m_w_completed;
  logic selected_m_w_sampled;
  logic selected_m_w_data;
  logic [AGE_W-1:0] age;

  // The endpoint channel checkers already own the canonical W burst-position
  // counters.  Reuse those public observations instead of maintaining three
  // duplicate role-local counters and active bits.
  wire [W_BEAT_W-1:0] s_current_w_beat = s_channel_w_beat;
  wire s_w_active = s_current_w_beat != 0;
  wire [W_BEAT_W-1:0] m_current_w_beat [2];
  assign m_current_w_beat[0] = m0_channel_w_beat;
  assign m_current_w_beat[1] = m1_channel_w_beat;
  wire m_w_active [2];
  assign m_w_active[0] = m_current_w_beat[0] != 0;
  assign m_w_active[1] = m_current_w_beat[1] != 0;

  wire [W_CANON_W-1:0] current_s_w_data = {
    s_w.data, s_w.strb, s_w.last,
    (PRESERVE_USER ? s_w.user : '0)
  };
  wire current_s_w_data_bit = watch_payload_bit < W_CANON_W ?
    current_s_w_data[watch_payload_bit] : 1'b0;
  wire m_w_data_bit [2];
  assign m_w_data_bit[0] = watch_payload_bit < W_CANON_W ?
    m_w_data[0][watch_payload_bit] : 1'b0;
  assign m_w_data_bit[1] = watch_payload_bit < W_CANON_W ?
    m_w_data[1][watch_payload_bit] : 1'b0;
  wire route0_now = route_hsk && watch_route == 0;
  wire route1_now = route_hsk && watch_route == 1;
  // The endpoint protocol tracker already owns the universal AW/completed-W
  // conservation state.  Decode its signed skew here instead of duplicating
  // six counters in the role tracker (one pair at the selected input and one
  // pair at each output).
  wire [PAIR_COUNT_W-1:0] s_aw_pending =
    s_pair_skew > 0 ? s_pair_skew[PAIR_COUNT_W-1:0] : '0;
  wire [WQ_COUNT_W-1:0] s_w_ahead =
    s_pair_skew < 0 ? -s_pair_skew : '0;
  wire signed [OUT_PAIR_SKEW_W-1:0] m_pair_skew [2];
  assign m_pair_skew[0] = m0_pair_skew;
  assign m_pair_skew[1] = m1_pair_skew;
  wire [MST_AW_COUNT_W-1:0] m_aw_pending [2];
  wire [MST_WQ_COUNT_W-1:0] m_w_ahead [2];
  assign m_aw_pending[0] = m_pair_skew[0] > 0 ?
    m_pair_skew[0][MST_AW_COUNT_W-1:0] : '0;
  assign m_aw_pending[1] = m_pair_skew[1] > 0 ?
    m_pair_skew[1][MST_AW_COUNT_W-1:0] : '0;
  assign m_w_ahead[0] = m_pair_skew[0] < 0 ? -m_pair_skew[0] : '0;
  assign m_w_ahead[1] = m_pair_skew[1] < 0 ? -m_pair_skew[1] : '0;

  // Shadow path for deleting the bounded payload queues later.  The chosen
  // output is selected with guarded muxes, never by indexing with the
  // decode-error value.  These signals do not feed the legacy queue proof.
  wire mapped_route = watch_route < DEST_ERROR;
  wire signed [OUT_PAIR_SKEW_W-1:0] selected_m_pair_skew =
    watch_route == 1 ? m1_pair_skew : m0_pair_skew;
  wire selected_m_w_valid = watch_route == 1 ? m_w_valid[1] :
    (watch_route == 0 ? m_w_valid[0] : 1'b0);
  wire selected_m_w_hsk_safe = watch_route == 1 ?
    (m_w_valid[1] && m_w_ready[1]) :
    (watch_route == 0 ?
      (m_w_valid[0] && m_w_ready[0]) : 1'b0);
  wire selected_m_w_last_hsk_safe = selected_m_w_hsk_safe &&
    (watch_route == 1 ? m_w[1].last :
      (watch_route == 0 ? m_w[0].last : 1'b0));
  wire [W_BEAT_W-1:0] selected_m_channel_w_beat =
    watch_route == 1 ? m1_channel_w_beat :
      (watch_route == 0 ? m0_channel_w_beat : '0);
  wire [W_CANON_W-1:0] selected_m_live_w_data =
    watch_route == 1 ? m_w_data[1] :
      (watch_route == 0 ? m_w_data[0] : '0);

  // The role payload selector spans all role channels.  Check that it names
  // a W bit before narrowing it to the endpoint pair selector width.
  wire pair_shadow_payload_in_range = watch_payload_bit < W_CANON_W;
  wire [W_PAYLOAD_BIT_W-1:0] pair_shadow_payload_idx =
    pair_shadow_payload_in_range ?
      watch_payload_bit[W_PAYLOAD_BIT_W-1:0] : '0;
  wire pair_shadow_s_live_payload_bit = pair_shadow_payload_in_range ?
    current_s_w_data[pair_shadow_payload_idx] : 1'b0;
  wire pair_shadow_m_live_payload_bit = pair_shadow_payload_in_range ?
    selected_m_live_w_data[pair_shadow_payload_idx] : 1'b0;

  // The public pair scalar is canonical {data,strb,last,user}, so USER owns
  // its least-significant USER_W bits.  Match the role contract by ignoring
  // those bits when USER preservation is disabled.
  wire pair_shadow_s_payload_bit =
    (!PRESERVE_USER && s_pair_w_payload_idx < USER_W) ?
      1'b0 : s_pair_w_payload_bit;
  wire pair_shadow_m_payload_bit =
    (!PRESERVE_USER && m_pair_w_payload_idx < USER_W) ?
      1'b0 : m_pair_w_payload_bit;

  // Live ownership includes count-parity fall-through before the selected AW
  // handshake.  A selected output route offer therefore keeps the proof
  // active under AW backpressure without assuming AWREADY.
  wire pair_shadow_s_live_owner =
    (role_selected && s_pair_pending_aw && s_pair_rank == 0) ||
    (select_now && s_pair_skew == 0);
  wire pair_shadow_m_live_owner =
    (routed && m_pair_pending_aw && m_pair_rank == 0) ||
    (route_offer && selected_m_pair_skew == 0);
  wire pair_shadow_s_w_offer = pair_shadow_s_live_owner &&
    s_w_valid && s_current_w_beat == watch_beat;
  wire pair_shadow_m_w_offer = pair_shadow_m_live_owner &&
    selected_m_w_valid && selected_m_channel_w_beat == watch_beat;
  wire pair_shadow_s_w_last_hsk = pair_shadow_s_live_owner &&
    s_w_last;
  wire pair_shadow_s_prefix_seed_now = select_now &&
    s_pair_skew == 0 && watch_beat < s_current_w_beat;
  wire pair_shadow_m_bound = role_selected && mapped_route &&
    (routed ||
      (route_offer && m_pair_pending_w && m_pair_rank == 0));

  wire selected_s_w_state =
    s_protocol_w_pending && s_protocol_w_rank == 0 && s_w_hsk;
  wire selected_s_w_bypass = select_now && s_aw_pending == 0 && s_w_hsk;
  wire selected_s_w = selected_s_w_state || selected_s_w_bypass;
  wire selected_s_w_beat =
    (selected_s_w_state && s_current_w_beat == watch_beat) ||
    (selected_s_w_bypass && s_current_w_beat == watch_beat);
  wire selected_s_w_last_now = selected_s_w && s_w_last;

  wire selected_m_w_state =
    routed && selected_m_w_pending && m_w_rank == 0 &&
    m_w_hsk[watch_route];
  wire selected_m_w_bypass =
    (route0_now && m_w_ahead[0] == 0 &&
      m_aw_pending[0] == 0 && m_w_hsk[0]) ||
    (route1_now && m_w_ahead[1] == 0 &&
      m_aw_pending[1] == 0 && m_w_hsk[1]);
  wire selected_m_w_beat =
    (selected_m_w_state &&
      m_current_w_beat[watch_route] == watch_beat) ||
    (selected_m_w_bypass &&
      m_current_w_beat[route1_now ? 1 : 0] == watch_beat);
  wire [W_CANON_W-1:0] current_m_w_data =
    selected_m_w_bypass ? (route1_now ? m_w_data[1] : m_w_data[0]) :
    m_w_data[watch_route];
  wire current_m_w_data_bit = watch_payload_bit < W_CANON_W ?
    current_m_w_data[watch_payload_bit] : 1'b0;
  wire selected_m_w_last_now =
    (selected_m_w_state && m_w_last[watch_route]) ||
    (route0_now && m_w_ahead[0] == 0 &&
      m_aw_pending[0] == 0 && m_w_last[0]) ||
    (route1_now && m_w_ahead[1] == 0 &&
      m_aw_pending[1] == 0 && m_w_last[1]);

  // B belongs to the selected AW only after the selected output W packet was
  // complete in prestate. A same-cycle WLAST therefore cannot authorize B.
  // Older same-ID B handshakes may still reduce m_b_rank below.
  wire m_b_has_credit = m_protocol_outstanding > m_b_rank;
  wire selected_m_b =
    routed && watch_route != DEST_ERROR && m_b_pending &&
    m_b_rank == 0 && selected_m_w_completed && m_b_has_credit &&
    m_b_offer[watch_route];
  wire [B_CANON_W-1:0] current_m_b_data =
    watch_route == 1 ? m_b_data[1] : m_b_data[0];
  wire [OUT_ID_W-1:0] m_protocol_wr_b_id =
    m_protocol_wr_b_bits[OUT_B_W-1 -: OUT_ID_W];
  wire [1:0] m_protocol_wr_b_resp =
    m_protocol_wr_b_bits[USER_W+1 -: 2];
  wire [USER_W-1:0] m_protocol_wr_b_user =
    m_protocol_wr_b_bits[USER_W-1:0];
  wire [B_CANON_W-1:0] m_protocol_wr_b_data = {
    m_protocol_wr_b_id[IN_ID_W-1:0], m_protocol_wr_b_resp,
    (PRESERVE_USER ? m_protocol_wr_b_user : '0)
  };
  wire selected_s_b = role_selected && s_protocol_rsp_visible;
  wire [1:0] effective_dest = watch_route;
  wire [B_CANON_W-1:0] current_s_b_data = {
    s_b.id, s_b.resp,
    (PRESERVE_USER ? s_b.user : '0)
  };
  wire current_m_b_data_bit = watch_payload_bit < B_CANON_W ?
    current_m_b_data[watch_payload_bit] : 1'b0;
  wire current_s_b_data_bit = watch_payload_bit < B_CANON_W ?
    current_s_b_data[watch_payload_bit] : 1'b0;
  wire m_protocol_wr_b_data_bit = watch_payload_bit < B_CANON_W ?
    m_protocol_wr_b_data[watch_payload_bit] : 1'b0;
  wire s_protocol_b_head =
    s_protocol_pending && s_protocol_w_complete &&
    s_protocol_rank == 0 && s_b_valid &&
    s_b.id == watch_id;
  wire s_b_stalled = s_b_valid && !s_b_ready;
  wire m_b_data_bit [2];
  assign m_b_data_bit[0] = watch_payload_bit < B_CANON_W ?
    m_b_data[0][watch_payload_bit] : 1'b0;
  assign m_b_data_bit[1] = watch_payload_bit < B_CANON_W ?
    m_b_data[1][watch_payload_bit] : 1'b0;

  // One-way alignment of otherwise independent FVIP ghost choices.  The
  // role occurrence constrains which endpoint pair witness observes it; the
  // converse is intentionally absent, and no DUT payload or availability is
  // assumed.  The source beat choice is already reused directly as
  // watch_beat, while the chosen output beat and both scalar indices need
  // explicit alignment.
  s_pair_shadow_source_aw_first: assume property (
    enable && select_now && mapped_route && s_pair_skew >= 0 |->
      s_pair_select_aw);
  s_pair_shadow_source_w_first: assume property (
    enable && select_now && mapped_route && s_pair_skew < 0 |->
      s_pair_pending_w && s_pair_rank == 0);
  s_pair_shadow_output_aw_first: assume property (
    enable && route_hsk && mapped_route && selected_m_pair_skew >= 0 |->
      m_pair_select_aw);
  s_pair_shadow_output_w_first: assume property (
    enable && route_offer && mapped_route && selected_m_pair_skew < 0 |->
      m_pair_pending_w && m_pair_rank == 0);
  s_pair_shadow_output_w_select_stalled_aw: assume property (
    enable && route_offer && !route_hsk && mapped_route &&
      selected_m_pair_skew == 0 && selected_m_w_last_hsk_safe |->
        m_pair_select_w);
  s_pair_shadow_output_beat_alignment: assume property (
    enable && mapped_route && (select_now || role_selected) |->
      m_pair_watch_beat == watch_beat);
  s_pair_shadow_source_payload_index_alignment: assume property (
    enable && mapped_route && (select_now || role_selected) &&
      pair_shadow_payload_in_range |->
        s_pair_w_payload_idx == pair_shadow_payload_idx);
  s_pair_shadow_output_payload_index_alignment: assume property (
    enable && mapped_route && (select_now || role_selected) &&
      pair_shadow_payload_in_range |->
        m_pair_w_payload_idx == pair_shadow_payload_idx);
  // Select the already-instantiated output protocol write observer on the
  // exact routed AW occurrence.  This is a one-way alignment of ghost
  // choices only; the endpoint selector never drives an AXI port.
  s_b_shadow_output_selection: assume property (
    enable && route_hsk && mapped_route |-> m_protocol_wr_select);

  // The routed role occurrence and the selected output endpoint observer are
  // sticky views of the same AW.  Isolate that state alignment before the B
  // occurrence proof so it does not repeatedly reconstruct selector history.
  a_endpoint_shadow_output_selected: assert property (
    routed && mapped_route |-> m_protocol_wr_selected);

  // State-shape lemmas keep the scalar payload proof downstream of endpoint
  // pair bookkeeping.  They add no role state and leave the legacy bounded
  // queue assertions below intact as an independent reference proof.
  a_pair_shadow_source_state: assert property (
    role_selected && mapped_route |->
      s_pair_pending_aw || s_pair_completed);
  a_pair_shadow_output_state: assert property (
    routed && mapped_route |->
      m_pair_pending_aw || m_pair_completed);

  // READY-independent occurrence and payload integrity for the selected W
  // beat.  A count-parity source prefix is exempt only in its AW-selection
  // cycle: the endpoint publishes that already-accepted rolling scalar on
  // the following cycle, after which the stored comparison applies.
  a_pair_shadow_w_offer_occurrence: assert property (
    pair_shadow_m_w_offer |->
      s_pair_w_payload_available || pair_shadow_s_w_offer ||
      pair_shadow_s_prefix_seed_now);
  a_pair_shadow_w_offer_integrity: assert property (
    pair_shadow_m_w_offer && pair_shadow_payload_in_range &&
      !pair_shadow_s_prefix_seed_now |->
        (s_pair_w_payload_available &&
          pair_shadow_m_live_payload_bit ==
            pair_shadow_s_payload_bit) ||
        (pair_shadow_s_w_offer &&
          pair_shadow_m_live_payload_bit ==
            pair_shadow_s_live_payload_bit));
  a_pair_shadow_w_prefix_hsk_integrity: assert property (
    pair_shadow_m_w_offer && pair_shadow_s_prefix_seed_now &&
      selected_m_w_hsk_safe && pair_shadow_payload_in_range |=>
        s_pair_w_payload_available &&
        pair_shadow_s_payload_bit ==
          $past(pair_shadow_m_live_payload_bit));

  // Output completion may follow an already completed source packet, a
  // same-cycle W-first AW join, or a same-cycle selected source WLAST.  It
  // must never get ahead of all three source-side forms.
  a_pair_shadow_w_completion_order: assert property (
    pair_shadow_m_live_owner && selected_m_w_last_hsk_safe |->
      s_pair_completed ||
      (select_now && s_pair_pending_w && s_pair_rank == 0) ||
      pair_shadow_s_w_last_hsk);

  // Once the output pair has a stored arbitrary-bit sample, the source pair
  // must already have the corresponding sample.  When the output packet is
  // complete, availability equality additionally proves beat occurrence in
  // both directions (and therefore matching packet length at the arbitrary
  // beat), independently of the legacy queues.
  a_pair_shadow_w_sample_occurrence: assert property (
    pair_shadow_m_bound && m_pair_w_payload_available |->
      s_pair_w_payload_available);
  a_pair_shadow_w_sample_integrity: assert property (
    pair_shadow_m_bound && pair_shadow_payload_in_range &&
      m_pair_w_payload_available && s_pair_w_payload_available |->
        pair_shadow_m_payload_bit == pair_shadow_s_payload_bit);
  a_pair_shadow_w_packet_order: assert property (
    pair_shadow_m_bound && (m_pair_pending_w || m_pair_completed) |->
      s_pair_completed);
  a_pair_shadow_w_packet_occurrence: assert property (
    pair_shadow_m_bound && (m_pair_pending_w || m_pair_completed) |->
      m_pair_w_payload_available == s_pair_w_payload_available);

  a_selected_w_integrity: assert property (
    selected_m_w_beat && watch_payload_bit < W_CANON_W |->
      (s_w_sampled && current_m_w_data_bit == selected_s_w_data) ||
      (selected_s_w_beat &&
        current_m_w_data_bit == current_s_w_data_bit));
  a_selected_w_completion: assert property (
    selected_m_w_last_now |->
      s_protocol_w_complete || selected_s_w_last_now);
  a_selected_sampled_w_integrity: assert property (
    selected_m_w_sampled && s_w_sampled &&
      watch_payload_bit < W_CANON_W |->
      selected_m_w_data == selected_s_w_data);
  a_selected_sampled_w_completion: assert property (
    selected_m_w_completed |-> s_protocol_w_complete);
  a_tracker_m_b_pending_rank: assert property (
    m_b_pending |-> m_b_has_credit);
  // Shadow replacement for the role-local B rank/sample machinery.  The
  // output endpoint observer is aligned to the routed AW above.  Its live
  // selected response handles a current offer; its sticky completion bit
  // validates the public response snapshot after an earlier handshake.
  // Split route establishment from the live-return residual so each zero-state
  // invariant can be proved and reused independently.
  a_endpoint_shadow_route_lifecycle: assert property (
    (route_pending ^ route_completed) ==
      (role_selected && mapped_route));
  a_endpoint_shadow_routed_equiv: assert property (
    routed == route_completed);
  // Before the selected AW reaches its destination, a matching source B can
  // only retire an older same-ID write.  Keep this at the raw port/rank
  // boundary so the public response-visible definition can consume it
  // without another response tracker or any READY/progress premise.
  a_endpoint_shadow_route_pending_b_is_older: assert property (
    route_pending |-> !s_protocol_b_head);
  // Inductive decomposition of the same invariant.  Selection establishes
  // the base case; while the route remains pending, a safe per-ID head stays
  // safe.  These use only the existing role/endpoint observer state.
  a_endpoint_shadow_route_pending_b_base: assert property (
    enable && select_now && mapped_route && !route_hsk |=>
      !s_protocol_b_head);
  a_endpoint_shadow_route_pending_b_hold: assert property (
    route_pending && !s_protocol_b_head && !route_hsk |=>
      !s_protocol_b_head);
  // Partition the preservation step on the full B-channel stall state.
  // VALID and BID both freeze in the stalled branch; the complementary
  // branch contains all possible response-slot admission or advancement.
  a_endpoint_shadow_route_pending_b_hold_stalled: assert property (
    route_pending && !s_protocol_b_head && !route_hsk && s_b_stalled |=>
      !s_protocol_b_head);
  a_endpoint_shadow_route_pending_b_hold_advancing: assert property (
    route_pending && !s_protocol_b_head && !route_hsk && !s_b_stalled |=>
      !s_protocol_b_head);
  // Exact disjoint split of !s_b_stalled.  With no current source-B offer a
  // new offer may appear on the next cycle; valid/ready consumes the current
  // offer and may advance the protocol observer rank.  Neither branch adds
  // state or assumes response progress.
  a_endpoint_shadow_route_pending_b_hold_empty: assert property (
    route_pending && !s_protocol_b_head && !route_hsk && !s_b_valid |=>
      !s_protocol_b_head);
  a_endpoint_shadow_route_pending_b_hold_consumed: assert property (
    route_pending && !s_protocol_b_head && !route_hsk &&
      s_b_valid && s_b_ready |=>
        !s_protocol_b_head);
  a_endpoint_shadow_route_pending_no_source_b: assert property (
    route_pending |-> !selected_s_b);
  a_endpoint_shadow_mapped_b_routed: assert property (
    selected_s_b && mapped_route |-> routed);
  a_endpoint_shadow_mapped_b_live_return: assert property (
    selected_s_b && mapped_route && routed &&
      !m_protocol_wr_completed |-> m_protocol_wr_rsp_visible);
  a_endpoint_shadow_mapped_b_occurrence: assert property (
    selected_s_b && mapped_route |->
      routed &&
      (m_protocol_wr_completed || m_protocol_wr_rsp_visible));
  a_endpoint_shadow_mapped_b: assert property (
    selected_s_b && mapped_route &&
      watch_payload_bit < B_CANON_W |->
        (routed && m_protocol_wr_completed ?
          current_s_b_data_bit == m_protocol_wr_b_data_bit :
          routed && m_protocol_wr_rsp_visible &&
            current_s_b_data_bit == current_m_b_data_bit));
  a_selected_mapped_b_occurrence: assert property (
    selected_s_b && effective_dest != DEST_ERROR |->
      m_b_sampled || selected_m_b);
  a_selected_mapped_b: assert property (
    selected_s_b && effective_dest != DEST_ERROR &&
      watch_payload_bit < B_CANON_W |->
      (m_b_sampled ?
        current_s_b_data_bit == selected_m_b_data :
        selected_m_b &&
          current_s_b_data_bit == current_m_b_data_bit));
  a_selected_error_b: assert property (
    selected_s_b && effective_dest == DEST_ERROR |->
      s_b.resp == axi_pkg::RESP_DECERR);

  if (ENABLE_PROGRESS) begin : g_progress
    a_selected_progress: assert property (
      role_selected && s_protocol_pending |-> age < MAX_DELAY);
  end

  c_select_dest0: cover property (select_now && s_route == 0);
  c_select_dest1: cover property (select_now && s_route == 1);
  c_select_error: cover property (select_now && s_route == DEST_ERROR);
  c_selected_w_complete: cover property (
    s_protocol_w_complete && selected_m_w_completed);
  c_pair_shadow_source_aw_first: cover property (
    select_now && mapped_route && s_pair_skew >= 0);
  c_pair_shadow_source_w_first: cover property (
    select_now && mapped_route && s_pair_skew < 0);
  c_pair_shadow_output_aw_first: cover property (
    route_hsk && selected_m_pair_skew >= 0);
  c_pair_shadow_output_w_first: cover property (
    route_offer && selected_m_pair_skew < 0);
  c_pair_shadow_output_stalled_w: cover property (
    route_offer && !route_hsk && pair_shadow_m_w_offer);
  c_pair_shadow_sample_compare: cover property (
    pair_shadow_m_bound && m_pair_w_payload_available &&
      s_pair_w_payload_available);
  c_complete: cover property (role_selected && s_protocol_completed);
  c_mapped_b_offer_stalled_live: cover property (
    selected_s_b && effective_dest != DEST_ERROR &&
    !s_b_ready && selected_m_b);
  c_mapped_b_offer_stalled_sampled: cover property (
    selected_s_b && effective_dest != DEST_ERROR &&
    !s_b_ready && m_b_sampled);
  c_error_b_offer_stalled: cover property (
    selected_s_b && effective_dest == DEST_ERROR && !s_b_ready);
  c_b_shadow_output_selection: cover property (
    route_hsk && mapped_route && m_protocol_wr_select);
  c_b_shadow_mapped_live_stalled: cover property (
    selected_s_b && mapped_route && !s_b_ready &&
      routed && !m_protocol_wr_completed && m_protocol_wr_rsp_visible);
  c_b_shadow_mapped_stored: cover property (
    selected_s_b && mapped_route && routed && m_protocol_wr_completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      routed <= 1'b0;
      m_b_rank <= '0;
      m_b_pending <= 1'b0;
      m_b_sampled <= 1'b0;
      selected_m_b_data <= '0;
      s_current_w_sampled <= 1'b0;
      s_current_w_data <= '0;
      s_w_sampled <= 1'b0;
      selected_s_w_data <= '0;
      m_w_rank <= '0;
      selected_m_w_pending <= 1'b0;
      selected_m_w_completed <= 1'b0;
      selected_m_w_sampled <= 1'b0;
      selected_m_w_data <= '0;
      age <= '0;
      for (int d = 0; d < 2; d++) begin
        m_current_w_sampled[d] <= 1'b0;
        m_current_w_data[d] <= '0;
        for (int q = 0; q < MST_WQ_DEPTH; q++) begin
          m_w_ahead_sampled[d][q] <= 1'b0;
          m_w_ahead_data[d][q] <= '0;
        end
      end
      for (int q = 0; q < WQ_DEPTH; q++) begin
        s_w_ahead_sampled[q] <= 1'b0;
        s_w_ahead_data[q] <= '0;
      end
    end else begin
      if (s_aw_hsk && s_w_ahead != 0) begin
        for (int q = 0; q < WQ_DEPTH-1; q++) begin
          s_w_ahead_sampled[q] <= s_w_ahead_sampled[q+1];
          s_w_ahead_data[q] <= s_w_ahead_data[q+1];
        end
      end
      if (s_w_last && s_aw_pending == 0 &&
          (!s_aw_hsk || s_w_ahead != 0)) begin
        s_w_ahead_sampled[s_w_ahead -
          ((s_aw_hsk && s_w_ahead != 0) ? 1'b1 : 1'b0)] <=
          s_current_w_sampled ||
          (s_w_hsk && s_current_w_beat == watch_beat);
        s_w_ahead_data[s_w_ahead -
          ((s_aw_hsk && s_w_ahead != 0) ? 1'b1 : 1'b0)] <=
          (s_w_hsk && s_current_w_beat == watch_beat) ?
            current_s_w_data_bit : s_current_w_data;
      end

      if (s_w_last) begin
        s_current_w_sampled <= 1'b0;
        s_current_w_data <= '0;
      end else if (s_w_hsk) begin
        if (s_current_w_beat == watch_beat) begin
          s_current_w_sampled <= 1'b1;
          s_current_w_data <= current_s_w_data_bit;
        end
      end
      for (int d = 0; d < 2; d++) begin
        if (m_aw_hsk[d] && m_w_ahead[d] != 0) begin
          for (int q = 0; q < MST_WQ_DEPTH-1; q++) begin
            m_w_ahead_sampled[d][q] <= m_w_ahead_sampled[d][q+1];
            m_w_ahead_data[d][q] <= m_w_ahead_data[d][q+1];
          end
        end
        if (m_w_last[d] && m_aw_pending[d] == 0 &&
            (!m_aw_hsk[d] || m_w_ahead[d] != 0)) begin
          m_w_ahead_sampled[d][m_w_ahead[d] -
            ((m_aw_hsk[d] && m_w_ahead[d] != 0) ? 1'b1 : 1'b0)] <=
            m_current_w_sampled[d] ||
            (m_w_hsk[d] && m_current_w_beat[d] == watch_beat);
          m_w_ahead_data[d][m_w_ahead[d] -
            ((m_aw_hsk[d] && m_w_ahead[d] != 0) ? 1'b1 : 1'b0)] <=
            (m_w_hsk[d] && m_current_w_beat[d] == watch_beat) ?
              m_w_data_bit[d] : m_current_w_data[d];
        end
        if (m_w_last[d]) begin
          m_current_w_sampled[d] <= 1'b0;
          m_current_w_data[d] <= '0;
        end else if (m_w_hsk[d]) begin
          if (m_current_w_beat[d] == watch_beat) begin
            m_current_w_sampled[d] <= 1'b1;
            m_current_w_data[d] <= m_w_data_bit[d];
          end
        end
      end

      if (select_now) begin
        if (s_w_ahead != 0) begin
          s_w_sampled <= s_w_ahead_sampled[0];
          selected_s_w_data <= s_w_ahead_data[0];
        end else begin
          if (s_aw_pending == 0 && (s_w_active || s_w_hsk)) begin
            s_w_sampled <= s_current_w_sampled;
            selected_s_w_data <= s_current_w_data;
          end
        end
        age <= '0;
        if (s_w_ahead == 0 && s_aw_pending == 0 && s_w_hsk) begin
          if (s_current_w_beat == watch_beat) begin
            s_w_sampled <= 1'b1;
            selected_s_w_data <= current_s_w_data_bit;
          end
        end
      end

      // The shared request-stream tracker already computed the selected
      // occurrence's route rank.  Its pulse is the exact output AW handshake
      // for this transaction, so the end-to-end tracker does not duplicate
      // route occupancy/rank state.
      if (route_hsk) begin
        routed <= 1'b1;
        if (m_w_ahead[watch_route] != 0) begin
          selected_m_w_pending <= 1'b0;
          selected_m_w_completed <= 1'b1;
          selected_m_w_sampled <= m_w_ahead_sampled[watch_route][0];
          selected_m_w_data <= m_w_ahead_data[watch_route][0];
          m_w_rank <= '0;
        end else if (m_aw_pending[watch_route] == 0 &&
            (m_w_active[watch_route] || m_w_hsk[watch_route])) begin
          selected_m_w_sampled <= m_current_w_sampled[watch_route];
          selected_m_w_data <= m_current_w_data[watch_route];
          if (m_w_hsk[watch_route] &&
              m_current_w_beat[watch_route] == watch_beat) begin
            selected_m_w_sampled <= 1'b1;
            selected_m_w_data <= m_w_data_bit[watch_route];
          end
          if (m_w_last[watch_route]) begin
            selected_m_w_pending <= 1'b0;
            selected_m_w_completed <= 1'b1;
          end else begin
            selected_m_w_pending <= 1'b1;
            m_w_rank <= '0;
          end
        end else begin
          selected_m_w_pending <= 1'b1;
          m_w_rank <= m_aw_pending[watch_route] -
            ((m_w_last[watch_route] && m_aw_pending[watch_route] != 0) ?
              1'b1 : 1'b0);
        end
        m_b_pending <= 1'b1;
        m_b_rank <= m_protocol_outstanding -
          ((m_b_watch[watch_route] && m_protocol_outstanding != 0) ?
            1'b1 : 1'b0);
      end

      if (s_protocol_w_pending && s_protocol_w_rank == 0 && s_w_hsk) begin
          if (s_current_w_beat == watch_beat) begin
            s_w_sampled <= 1'b1;
            selected_s_w_data <= current_s_w_data_bit;
          end
      end

      if (!route_hsk && selected_m_w_pending && m_w_hsk[watch_route]) begin
        if (m_w_rank != 0) begin
          if (m_w_last[watch_route])
            m_w_rank <= m_w_rank - 1'b1;
        end else begin
          if (m_current_w_beat[watch_route] == watch_beat) begin
            selected_m_w_sampled <= 1'b1;
            selected_m_w_data <= m_w_data_bit[watch_route];
          end
          if (m_w_last[watch_route]) begin
            selected_m_w_pending <= 1'b0;
            selected_m_w_completed <= 1'b1;
          end
        end
      end

      if (!route_hsk && m_b_pending && m_b_watch[watch_route] &&
          m_b_has_credit) begin
        if (m_b_rank != 0) begin
          m_b_rank <= m_b_rank - 1'b1;
        end else if (selected_m_w_completed) begin
          m_b_pending <= 1'b0;
          m_b_sampled <= 1'b1;
          selected_m_b_data <= m_b_data_bit[watch_route];
        end
      end

      if (role_selected && s_protocol_pending &&
          ENABLE_PROGRESS && age < MAX_DELAY)
        age <= age + 1'b1;
    end
  end
endmodule
