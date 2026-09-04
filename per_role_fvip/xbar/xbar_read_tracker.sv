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
  parameter logic [DATA_W-1:0] ERROR_RDATA = DATA_W'(64'hca11_ab1e_bad_cab1e),
  parameter int PAYLOAD_BIT_W = 1,
  localparam int WATCH_W = (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN),
  localparam int IN_AW_W = IN_ID_W + ADDR_W + 35 + USER_W,
  localparam int IN_W_W = DATA_W + DATA_W/8 + 1 + USER_W,
  localparam int IN_AR_W = IN_ID_W + ADDR_W + 29 + USER_W,
  localparam int IN_B_W = IN_ID_W + 2 + USER_W,
  localparam int IN_R_W = IN_ID_W + DATA_W + 3 + USER_W,
  localparam int IN_REQ_W = IN_AW_W + IN_W_W + IN_AR_W + 5,
  localparam int IN_RSP_W = IN_B_W + IN_R_W + 5,
  localparam int OUT_REQ_W = IN_REQ_W + 2*(OUT_ID_W-IN_ID_W),
  localparam int OUT_RSP_W = IN_RSP_W + 2*(OUT_ID_W-IN_ID_W),
  localparam int IN_STATE_MAX =
    MAX_OUTSTANDING + MAX_AW_AHEAD + MAX_W_AHEAD,
  localparam int IN_STATE_W =
    (IN_STATE_MAX < 2) ? 1 : $clog2(IN_STATE_MAX + 1),
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
  input logic [IN_ID_W-1:0] watch_id,
  input logic [WATCH_W-1:0] watch_beat,
  input logic [PAYLOAD_BIT_W-1:0] watch_payload_bit,
  input logic role_selected,
  input logic s_protocol_pending,
  input logic s_protocol_completed,
  input logic [IN_STATE_W-1:0] s_protocol_rank,
  input logic [7:0] s_protocol_beat,
  input logic s_protocol_rsp_visible,
  input logic [OUT_STATE_W-1:0] m_protocol_outstanding,
  input logic select_now,
  input logic route_hsk,
  input logic [IN_REQ_W-1:0] s_req_bits,
  input logic [IN_RSP_W-1:0] s_rsp_bits,
  input logic [OUT_REQ_W-1:0] m0_req_bits,
  input logic [OUT_RSP_W-1:0] m0_rsp_bits,
  input logic [OUT_REQ_W-1:0] m1_req_bits,
  input logic [OUT_RSP_W-1:0] m1_rsp_bits
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam logic [1:0] DEST_ERROR = 2'd2;
  localparam int MST_MAX = 2 * MAX_OUTSTANDING;
  localparam int MST_COUNT_W = (MST_MAX < 2) ? 1 : $clog2(MST_MAX + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);
  localparam int BEAT_COUNT_W =
    (MAX_BURST_LEN < 1) ? 1 : $clog2(MAX_BURST_LEN + 1);
  localparam int R_CANON_W = IN_ID_W + DATA_W + 2 + 1 + USER_W;

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [DATA_W/8-1:0] strb_t;
  typedef logic [USER_W-1:0] user_t;
  typedef logic [IN_ID_W-1:0] in_id_t;
  typedef logic [OUT_ID_W-1:0] out_id_t;
  `AXI_TYPEDEF_ALL_CT(in_axi, in_req_t, in_rsp_t,
    addr_t, in_id_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL_CT(out_axi, out_req_t, out_rsp_t,
    addr_t, out_id_t, data_t, strb_t, user_t)
  in_req_t s_req;
  in_rsp_t s_rsp;
  out_req_t m0_req, m1_req;
  out_rsp_t m0_rsp, m1_rsp;
  assign s_req = s_req_bits;
  assign s_rsp = s_rsp_bits;
  assign m0_req = m0_req_bits;
  assign m0_rsp = m0_rsp_bits;
  assign m1_req = m1_req_bits;
  assign m1_rsp = m1_rsp_bits;

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

  wire [1:0] s_route = decode(s_req.ar.addr);

  wire [1:0] m_r_offer;
  wire [1:0] m_r_last_offer;
  wire [1:0] m_r_watch;
  wire [1:0] m_r_last_watch;
  wire [R_CANON_W-1:0] m_r_data [2];
  assign m_r_offer[0] =
    enable && m0_rsp.r_valid &&
    m0_rsp.r.id[OUT_ID_W-1] == source &&
    m0_rsp.r.id[IN_ID_W-1:0] == watch_id;
  assign m_r_offer[1] =
    enable && m1_rsp.r_valid &&
    m1_rsp.r.id[OUT_ID_W-1] == source &&
    m1_rsp.r.id[IN_ID_W-1:0] == watch_id;
  assign m_r_watch[0] = m_r_offer[0] && m0_req.r_ready;
  assign m_r_watch[1] = m_r_offer[1] && m1_req.r_ready;
  assign m_r_last_offer[0] = m_r_offer[0] && m0_rsp.r.last;
  assign m_r_last_offer[1] = m_r_offer[1] && m1_rsp.r.last;
  assign m_r_last_watch[0] = m_r_watch[0] && m0_rsp.r.last;
  assign m_r_last_watch[1] = m_r_watch[1] && m1_rsp.r.last;
  assign m_r_data[0] = {
    m0_rsp.r.id[IN_ID_W-1:0], m0_rsp.r.data,
    m0_rsp.r.resp, m0_rsp.r.last,
    (PRESERVE_USER ? m0_rsp.r.user : '0)
  };
  assign m_r_data[1] = {
    m1_rsp.r.id[IN_ID_W-1:0], m1_rsp.r.data,
    m1_rsp.r.resp, m1_rsp.r.last,
    (PRESERVE_USER ? m1_rsp.r.user : '0)
  };

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
    m_rsp_rank == 0 && m_rsp_has_credit && m_r_offer[watch_route];
  wire selected_m_r_last_now =
    selected_m_r && m_r_last_offer[watch_route];
  wire selected_m_beat =
    selected_m_r && m_rsp_beat == watch_beat;
  wire [R_CANON_W-1:0] current_m_r_data =
    watch_route == 1 ? m_r_data[1] : m_r_data[0];
  wire selected_s_r = role_selected && s_protocol_rsp_visible;
  wire selected_s_beat = selected_s_r &&
    s_protocol_beat == watch_beat;
  wire [1:0] effective_dest = watch_route;
  wire [R_CANON_W-1:0] current_s_r_data = {
    s_rsp.r.id, s_rsp.r.data, s_rsp.r.resp,
    s_rsp.r.last, (PRESERVE_USER ? s_rsp.r.user : '0)
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
    selected_s_r && s_rsp.r.last && effective_dest != DEST_ERROR |->
      m_rsp_completed || selected_m_r_last_now);
  a_selected_error_response: assert property (
    selected_s_r && effective_dest == DEST_ERROR |->
      s_rsp.r.resp == axi_pkg::RESP_DECERR &&
      s_rsp.r.data == ERROR_RDATA);

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
    !s_req.r_ready && selected_m_beat);
  c_mapped_r_offer_stalled_sampled: cover property (
    selected_s_beat && effective_dest != DEST_ERROR &&
    !s_req.r_ready && m_beat_sampled);
  c_error_r_offer_stalled: cover property (
    selected_s_r && effective_dest == DEST_ERROR && !s_req.r_ready);

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
          ((m_r_last_watch[watch_route] &&
            m_protocol_outstanding != 0) ? 1'b1 : 1'b0);
        m_rsp_beat <= '0;
      end

      if (!route_hsk && m_rsp_pending && m_rsp_has_credit &&
          m_r_watch[watch_route]) begin
        if (m_rsp_rank != 0) begin
          if (m_r_last_watch[watch_route])
            m_rsp_rank <= m_rsp_rank - 1'b1;
        end else begin
          if (m_rsp_beat == watch_beat) begin
            m_beat_sampled <= 1'b1;
            m_beat_data <= current_m_r_data_bit;
          end
          if (m_r_last_watch[watch_route]) begin
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
