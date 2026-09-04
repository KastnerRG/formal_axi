`include "axi/typedef.svh"

// End-to-end selected read transaction for one arbitrarily chosen crossbar
// source port.
// Request-stream conservation is checked separately.  This tracker follows an
// arbitrary same-ID request through its decoded output response and back to
// the originating input, or checks the local DECERR path for an unmapped AR.
module fv_xbar_read_tracker #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int IN_ID_W = 4,
  parameter int OUT_ID_W = IN_ID_W + 1,
  parameter int USER_W = 1,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_OUTPUT_OUTSTANDING = MAX_OUTSTANDING,
  parameter int MAX_OUTPUT_AW_AHEAD = 4,
  parameter int MAX_OUTPUT_W_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 32,
  parameter logic [ADDR_W-1:0] ADDR0_BASE = '0,
  parameter logic [ADDR_W-1:0] ADDR1_BASE = ADDR_W'(32'h0001_0000),
  parameter logic [ADDR_W-1:0] ADDR_MASK = ADDR_W'(32'hffff_0000),
  parameter logic [1:0] DEFAULT_ENABLE = 2'b00,
  parameter logic [1:0] DEFAULT_DEST = 2'b00,
  parameter bit PRESERVE_USER = 1'b1,
  parameter logic [DATA_W-1:0] ERROR_RDATA = DATA_W'(64'hca11_ab1e_bad_cab1e),
  parameter int PAYLOAD_BIT_W = 1,
  localparam int WATCH_W = (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN),
  localparam int OUT_STATE_MAX =
    MAX_OUTPUT_OUTSTANDING + MAX_OUTPUT_AW_AHEAD + MAX_OUTPUT_W_AHEAD,
  localparam int OUT_STATE_W =
    (OUT_STATE_MAX < 2) ? 1 : $clog2(OUT_STATE_MAX + 1)
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
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);
  localparam int BEAT_COUNT_W =
    (MAX_BURST_LEN < 1) ? 1 : $clog2(MAX_BURST_LEN + 1);
  localparam int R_CANON_W = axi_pkg::r_width(DATA_W, IN_ID_W, USER_W);

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [USER_W-1:0] user_t;
  typedef logic [IN_ID_W-1:0] in_id_t;
  typedef logic [OUT_ID_W-1:0] out_id_t;
  `AXI_TYPEDEF_AR_CHAN_T(in_ar_t, addr_t, in_id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(in_r_t, data_t, in_id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(out_r_t, data_t, out_id_t, user_t)

  in_ar_t s_ar;
  in_r_t s_r;
  out_r_t m0_r, m1_r;
  assign s_ar = source ? s1_view.live_ar : s0_view.live_ar;
  assign s_r = source ? s1_view.live_r : s0_view.live_r;
  assign m0_r = m0_view.live_r;
  assign m1_r = m1_view.live_r;
  wire s_r_ready = source ? s1_view.live_r_ready : s0_view.live_r_ready;
  wire m0_r_valid = m0_view.live_r_valid;
  wire m0_r_ready = m0_view.live_r_ready;
  wire m1_r_valid = m1_view.live_r_valid;
  wire m1_r_ready = m1_view.live_r_ready;

  wire [IN_ID_W-1:0] watch_id =
    source ? s1_view.rd_watch_id : s0_view.rd_watch_id;
  wire [7:0] selected_s_watch_beat =
    source ? s1_view.rd_beat_idx : s0_view.rd_beat_idx;
  wire [WATCH_W-1:0] watch_beat =
    selected_s_watch_beat[WATCH_W-1:0];
  wire s_protocol_pending =
    source ? s1_view.rd_pending : s0_view.rd_pending;
  wire s_protocol_completed =
    source ? s1_view.rd_completed : s0_view.rd_completed;
  wire [7:0] s_protocol_beat =
    source ? s1_view.rd_rsp_beat : s0_view.rd_rsp_beat;
  wire s_protocol_rsp_visible =
    source ? s1_view.rd_rsp_visible : s0_view.rd_rsp_visible;
  wire [OUT_STATE_W-1:0] m_protocol_outstanding =
    watch_route == 1 ? m1_view.rd_outstanding : m0_view.rd_outstanding;

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

  wire [1:0] s_route = decode(s_ar.addr);

  wire [1:0] m_r_offer;
  wire [1:0] m_r_last_offer;
  wire [1:0] m_r_watch;
  wire [1:0] m_r_last_watch;
  wire [R_CANON_W-1:0] m_r_data [2];
  assign m_r_offer[0] =
    enable && m0_r_valid &&
    m0_r.id[OUT_ID_W-1] == source &&
    m0_r.id[IN_ID_W-1:0] == watch_id;
  assign m_r_offer[1] =
    enable && m1_r_valid &&
    m1_r.id[OUT_ID_W-1] == source &&
    m1_r.id[IN_ID_W-1:0] == watch_id;
  assign m_r_watch[0] = m_r_offer[0] && m0_r_ready;
  assign m_r_watch[1] = m_r_offer[1] && m1_r_ready;
  assign m_r_last_offer[0] = m_r_offer[0] && m0_r.last;
  assign m_r_last_offer[1] = m_r_offer[1] && m1_r.last;
  assign m_r_last_watch[0] = m_r_watch[0] && m0_r.last;
  assign m_r_last_watch[1] = m_r_watch[1] && m1_r.last;
  assign m_r_data[0] = {
    m0_r.id[IN_ID_W-1:0], m0_r.data,
    m0_r.resp, m0_r.last,
    (PRESERVE_USER ? m0_r.user : '0)
  };
  assign m_r_data[1] = {
    m1_r.id[IN_ID_W-1:0], m1_r.data,
    m1_r.resp, m1_r.last,
    (PRESERVE_USER ? m1_r.user : '0)
  };
  wire selected_m_r_offer = watch_route == 0 ? m_r_offer[0] :
    watch_route == 1 ? m_r_offer[1] : 1'b0;
  wire selected_m_r_last_offer = watch_route == 0 ? m_r_last_offer[0] :
    watch_route == 1 ? m_r_last_offer[1] : 1'b0;
  wire selected_m_r_watch = watch_route == 0 ? m_r_watch[0] :
    watch_route == 1 ? m_r_watch[1] : 1'b0;
  wire selected_m_r_last_watch = watch_route == 0 ? m_r_last_watch[0] :
    watch_route == 1 ? m_r_last_watch[1] : 1'b0;

  logic routed;

  logic [MST_COUNT_W-1:0] m_rsp_rank;
  logic [BEAT_COUNT_W-1:0] m_rsp_beat;
  logic m_rsp_pending, m_rsp_completed;

  logic m_beat_sampled;
  logic m_beat_data;
  logic [AGE_W-1:0] age;

  // The output protocol forbids a response without pre-existing request
  // credit. Therefore a response on the selected route handshake cannot be
  // the newly routed request; it is either older traffic or illegal.
  wire m_rsp_has_credit = m_protocol_outstanding > m_rsp_rank;
  wire selected_m_r =
    routed && watch_route != DEST_ERROR && m_rsp_pending &&
    m_rsp_rank == 0 && m_rsp_has_credit && selected_m_r_offer;
  wire selected_m_r_last_now =
    selected_m_r && selected_m_r_last_offer;
  wire selected_m_beat =
    selected_m_r && m_rsp_beat == watch_beat;
  wire [R_CANON_W-1:0] current_m_r_data =
    watch_route == 1 ? m_r_data[1] : m_r_data[0];
  wire selected_s_r = role_selected && s_protocol_rsp_visible;
  wire selected_s_beat = selected_s_r &&
    s_protocol_beat == watch_beat;
  wire [1:0] effective_dest = watch_route;
  wire [R_CANON_W-1:0] current_s_r_data = {
    s_r.id, s_r.data, s_r.resp,
    s_r.last, (PRESERVE_USER ? s_r.user : '0)
  };
  wire current_m_r_data_bit = watch_payload_bit < R_CANON_W ?
    current_m_r_data[watch_payload_bit] : 1'b0;
  wire current_s_r_data_bit = watch_payload_bit < R_CANON_W ?
    current_s_r_data[watch_payload_bit] : 1'b0;

  // Occurrence and payload are split so the small ordering cone can be proved
  // independently and reused. Once the selected output beat was accepted,
  // its captured bit has priority over any unrelated later live offer.
  a_tracker_m_rsp_pending_rank: assert property (
    m_rsp_pending |-> m_rsp_has_credit);
  a_selected_mapped_response_occurrence: assert property (
    selected_s_beat && effective_dest != DEST_ERROR |->
      m_beat_sampled || selected_m_beat);
  a_selected_mapped_response_data: assert property (
    selected_s_beat && effective_dest != DEST_ERROR &&
      watch_payload_bit < R_CANON_W |->
      (m_beat_sampled ?
        current_s_r_data_bit == m_beat_data :
        selected_m_beat &&
          current_s_r_data_bit == current_m_r_data_bit));
  a_selected_mapped_response_completion: assert property (
    selected_s_r && s_r.last && effective_dest != DEST_ERROR |->
      m_rsp_completed || selected_m_r_last_now);
  a_selected_error_response: assert property (
    selected_s_r && effective_dest == DEST_ERROR |->
      s_r.resp == axi_pkg::RESP_DECERR &&
      s_r.data == ERROR_RDATA);

  if (ENABLE_PROGRESS) begin : g_progress
    a_selected_progress: assert property (
      role_selected && s_protocol_pending |-> age < MAX_DELAY);
  end

  c_select_dest0: cover property (select_now && s_route == 0);
  c_select_dest1: cover property (select_now && s_route == 1);
  c_select_error: cover property (select_now && s_route == DEST_ERROR);
  c_complete: cover property (role_selected && s_protocol_completed);
  c_mapped_r_offer_stalled_live: cover property (
    selected_s_beat && effective_dest != DEST_ERROR &&
    !s_r_ready && selected_m_beat);
  c_mapped_r_offer_stalled_sampled: cover property (
    selected_s_beat && effective_dest != DEST_ERROR &&
    !s_r_ready && m_beat_sampled);
  c_error_r_offer_stalled: cover property (
    selected_s_r && effective_dest == DEST_ERROR && !s_r_ready);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      routed <= 1'b0;
      m_rsp_rank <= '0;
      m_rsp_beat <= '0;
      m_rsp_pending <= 1'b0;
      m_rsp_completed <= 1'b0;
      m_beat_sampled <= 1'b0;
      m_beat_data <= '0;
      age <= '0;
    end else begin
      if (select_now) begin
        age <= '0;
      end

      if (route_hsk) begin
        routed <= 1'b1;
        m_rsp_pending <= 1'b1;
        m_rsp_rank <= m_protocol_outstanding -
          ((selected_m_r_last_watch &&
            m_protocol_outstanding != 0) ? 1'b1 : 1'b0);
        m_rsp_beat <= '0;
      end

      if (!route_hsk && m_rsp_pending && m_rsp_has_credit &&
          selected_m_r_watch) begin
        if (m_rsp_rank != 0) begin
          if (selected_m_r_last_watch)
            m_rsp_rank <= m_rsp_rank - 1'b1;
        end else begin
          if (m_rsp_beat == watch_beat) begin
            m_beat_sampled <= 1'b1;
            m_beat_data <= current_m_r_data_bit;
          end
          if (selected_m_r_last_watch) begin
            m_rsp_pending <= 1'b0;
            m_rsp_completed <= 1'b1;
          end else begin
            if (m_rsp_beat < MAX_BURST_LEN)
              m_rsp_beat <= m_rsp_beat + 1'b1;
          end
        end
      end

      if (role_selected && s_protocol_pending &&
          ENABLE_PROGRESS && age < MAX_DELAY)
        age <= age + 1'b1;
    end
  end
endmodule
