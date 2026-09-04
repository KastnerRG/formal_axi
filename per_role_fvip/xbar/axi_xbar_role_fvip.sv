`include "axi/typedef.svh"

// Functionality for one arbitrarily selected input of a 2x2 crossbar. One
// arbitrary destination and ID domain reduces each request channel to a
// single conservation tracker while still covering all four routes.
module fv_axi_xbar_source_role #(
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
  parameter bit PRESERVE_REGION = 1'b1,
  parameter bit PRESERVE_USER = 1'b1,
  parameter logic [DATA_W-1:0] ERROR_RDATA = DATA_W'(64'hca11_ab1e_bad_cab1e),
  localparam int IN_AW_W = IN_ID_W + ADDR_W + 35 + USER_W,
  localparam int IN_W_W = DATA_W + DATA_W/8 + 1 + USER_W,
  localparam int IN_AR_W = IN_ID_W + ADDR_W + 29 + USER_W,
  localparam int IN_B_W = IN_ID_W + 2 + USER_W,
  localparam int IN_R_W = IN_ID_W + DATA_W + 3 + USER_W,
  localparam int IN_REQ_W = IN_AW_W + IN_W_W + IN_AR_W + 5,
  localparam int IN_RSP_W = IN_B_W + IN_R_W + 5,
  localparam int OUT_B_W = OUT_ID_W + 2 + USER_W,
  localparam int OUT_REQ_W = IN_REQ_W + 2*(OUT_ID_W-IN_ID_W),
  localparam int OUT_RSP_W = IN_RSP_W + 2*(OUT_ID_W-IN_ID_W),
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
  input logic source,
  input logic signed [IN_PAIR_SKEW_W-1:0] s_pair_skew,
  input logic signed [OUT_PAIR_SKEW_W-1:0] m0_pair_skew,
  input logic signed [OUT_PAIR_SKEW_W-1:0] m1_pair_skew,
  input logic s_pair_select_aw,
  input logic s_pair_pending_aw,
  input logic s_pair_pending_w,
  input logic s_pair_completed,
  input logic [IN_STATE_W-1:0] s_pair_rank,
  input logic [W_PAYLOAD_BIT_W-1:0] s_pair_w_payload_idx,
  input logic s_pair_w_payload_bit,
  input logic s_pair_w_payload_available,
  input logic m0_pair_select_aw,
  input logic m1_pair_select_aw,
  input logic m0_pair_select_w,
  input logic m1_pair_select_w,
  input logic m0_pair_pending_aw,
  input logic m1_pair_pending_aw,
  input logic m0_pair_pending_w,
  input logic m1_pair_pending_w,
  input logic m0_pair_completed,
  input logic m1_pair_completed,
  input logic [OUT_STATE_W-1:0] m0_pair_rank,
  input logic [OUT_STATE_W-1:0] m1_pair_rank,
  input logic [7:0] m0_pair_watch_beat,
  input logic [7:0] m1_pair_watch_beat,
  input logic [W_PAYLOAD_BIT_W-1:0] m0_pair_w_payload_idx,
  input logic [W_PAYLOAD_BIT_W-1:0] m1_pair_w_payload_idx,
  input logic m0_pair_w_payload_bit,
  input logic m1_pair_w_payload_bit,
  input logic m0_pair_w_payload_available,
  input logic m1_pair_w_payload_available,
  input logic [W_BEAT_W-1:0] s_channel_w_beat,
  input logic [W_BEAT_W-1:0] m0_channel_w_beat,
  input logic [W_BEAT_W-1:0] m1_channel_w_beat,
  input logic s_rd_select,
  input logic [IN_ID_W-1:0] s_rd_watch_id,
  input logic [7:0] s_rd_watch_beat,
  input logic s_rd_pending,
  input logic s_rd_completed,
  input logic [IN_STATE_W-1:0] s_rd_rank,
  input logic [7:0] s_rd_rsp_beat,
  input logic s_rd_rsp_visible,
  input logic s_wr_select,
  input logic [IN_ID_W-1:0] s_wr_watch_id,
  input logic [7:0] s_wr_watch_beat,
  input logic s_wr_pending,
  input logic s_wr_completed,
  input logic [IN_STATE_W-1:0] s_wr_rank,
  input logic s_wr_data_pending,
  input logic [IN_STATE_W-1:0] s_wr_data_rank,
  input logic s_wr_data_complete,
  input logic s_wr_rsp_visible,
  input logic [OUT_ID_W-1:0] m0_rd_watch_id,
  input logic [OUT_ID_W-1:0] m1_rd_watch_id,
  input logic [OUT_STATE_W-1:0] m0_rd_outstanding,
  input logic [OUT_STATE_W-1:0] m1_rd_outstanding,
  input logic [OUT_ID_W-1:0] m0_wr_watch_id,
  input logic [OUT_ID_W-1:0] m1_wr_watch_id,
  input logic [OUT_STATE_W-1:0] m0_wr_outstanding,
  input logic [OUT_STATE_W-1:0] m1_wr_outstanding,
  input logic m0_wr_select,
  input logic m1_wr_select,
  input logic m0_wr_selected,
  input logic m1_wr_selected,
  input logic m0_wr_completed,
  input logic m1_wr_completed,
  input logic m0_wr_rsp_visible,
  input logic m1_wr_rsp_visible,
  input logic [OUT_B_W-1:0] m0_wr_b_bits,
  input logic [OUT_B_W-1:0] m1_wr_b_bits,
  input logic [IN_REQ_W-1:0] s_req_bits,
  input logic [IN_RSP_W-1:0] s_rsp_bits,
  input logic [OUT_REQ_W-1:0] m0_req_bits,
  input logic [OUT_RSP_W-1:0] m0_rsp_bits,
  input logic [OUT_REQ_W-1:0] m1_req_bits,
  input logic [OUT_RSP_W-1:0] m1_rsp_bits
);
  localparam int AW_CANON_W =
    IN_ID_W + ADDR_W + 8 + 3 + 2 + 1 + 4 + 3 + 4 + 4 + 6 + USER_W;
  localparam int AR_CANON_W =
    IN_ID_W + ADDR_W + 8 + 3 + 2 + 1 + 4 + 3 + 4 + 4 + USER_W;
  localparam int R_CANON_W = IN_ID_W + DATA_W + 2 + 1 + USER_W;
  localparam int W_CANON_W = DATA_W + DATA_W/8 + 1 + USER_W;
  localparam int B_CANON_W = IN_ID_W + 2 + USER_W;
  localparam int ROLE_PAYLOAD_W0 =
    (AW_CANON_W > R_CANON_W) ? AW_CANON_W : R_CANON_W;
  localparam int ROLE_PAYLOAD_W1 =
    (W_CANON_W > B_CANON_W) ? W_CANON_W : B_CANON_W;
  localparam int ROLE_PAYLOAD_W =
    (ROLE_PAYLOAD_W0 > ROLE_PAYLOAD_W1) ?
      ROLE_PAYLOAD_W0 : ROLE_PAYLOAD_W1;
  localparam int PAYLOAD_BIT_W =
    (ROLE_PAYLOAD_W < 2) ? 1 : $clog2(ROLE_PAYLOAD_W);
  localparam int WATCH_W =
    (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN);
  localparam logic [1:0] DEST_ERROR = 2'd2;

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
      decode = 2'd2;
  endfunction

  (* anyconst *) logic watch_write;
  (* anyconst *) logic [1:0] watch_route;
  (* anyconst *) logic [PAYLOAD_BIT_W-1:0] watch_payload_bit;
  s_watch_write_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_write));
  s_watch_route_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_route));
  s_watch_route_range: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    watch_route <= DEST_ERROR);
  s_watch_payload_bit_constant: assume property (
    @(posedge clk) disable iff ($isunknown(rstn))
      $stable(watch_payload_bit));
  s_watch_payload_bit_range: assume property (
    @(posedge clk) disable iff ($isunknown(rstn))
      watch_payload_bit < ROLE_PAYLOAD_W);

  // Reuse the generic endpoint observer domain and selection pulse. Filtering
  // by the role's arbitrary route preserves eligibility for every route while
  // avoiding a second role-local transaction selector.
  wire [IN_ID_W-1:0] watch_id =
    watch_write ? s_wr_watch_id : s_rd_watch_id;
  wire [WATCH_W-1:0] watch_beat = watch_write ?
    s_wr_watch_beat[WATCH_W-1:0] : s_rd_watch_beat[WATCH_W-1:0];
  wire [OUT_ID_W-1:0] selected_m_watch_id = watch_write ?
    (watch_route == 1 ? m1_wr_watch_id : m0_wr_watch_id) :
    (watch_route == 1 ? m1_rd_watch_id : m0_rd_watch_id);
  wire selected_m_wr_select = watch_route == 1 ? m1_wr_select :
    (watch_route == 0 ? m0_wr_select : 1'b0);
  wire selected_m_wr_selected = watch_route == 1 ? m1_wr_selected :
    (watch_route == 0 ? m0_wr_selected : 1'b0);
  wire selected_m_wr_completed = watch_route == 1 ? m1_wr_completed :
    (watch_route == 0 ? m0_wr_completed : 1'b0);
  wire selected_m_wr_rsp_visible = watch_route == 1 ? m1_wr_rsp_visible :
    (watch_route == 0 ? m0_wr_rsp_visible : 1'b0);
  wire [OUT_B_W-1:0] selected_m_wr_b_bits = watch_route == 1 ?
    m1_wr_b_bits : (watch_route == 0 ? m0_wr_b_bits : '0);
  wire output_watch_matches = watch_route == DEST_ERROR ||
    selected_m_watch_id == {source, watch_id};
  wire selected_input_hsk = watch_write ?
    (s_wr_select && decode(s_req.aw.addr) == watch_route &&
      output_watch_matches) :
    (s_rd_select && decode(s_req.ar.addr) == watch_route &&
      output_watch_matches);
  logic role_selected;
  wire select_now = selected_input_hsk && !role_selected;
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn)
      role_selected <= 1'b0;
    else if (select_now)
      role_selected <= 1'b1;
  end

  wire s_aw_valid = s_req.aw_valid &&
    decode(s_req.aw.addr) == watch_route &&
    s_req.aw.id == watch_id;
  wire s_aw_hsk = s_aw_valid && s_rsp.aw_ready;
  wire m_aw_valid = watch_route == 1 ?
    (m1_req.aw_valid &&
      m1_req.aw.id[OUT_ID_W-1] == source &&
      m1_req.aw.id[IN_ID_W-1:0] == watch_id) :
    (watch_route == 0 && m0_req.aw_valid &&
      m0_req.aw.id[OUT_ID_W-1] == source &&
      m0_req.aw.id[IN_ID_W-1:0] == watch_id);
  wire m_aw_hsk = m_aw_valid &&
    (watch_route == 1 ? m1_rsp.aw_ready : m0_rsp.aw_ready);
  wire [AW_CANON_W-1:0] s_aw_data = {
    s_req.aw.id, s_req.aw.addr, s_req.aw.len,
    s_req.aw.size, s_req.aw.burst, s_req.aw.lock,
    s_req.aw.cache, s_req.aw.prot, s_req.aw.qos,
    (PRESERVE_REGION ? s_req.aw.region : 4'b0),
    s_req.aw.atop, (PRESERVE_USER ? s_req.aw.user : '0)
  };
  wire [AW_CANON_W-1:0] m0_aw_data = {
    m0_req.aw.id[IN_ID_W-1:0], m0_req.aw.addr, m0_req.aw.len,
    m0_req.aw.size, m0_req.aw.burst, m0_req.aw.lock, m0_req.aw.cache,
    m0_req.aw.prot, m0_req.aw.qos,
    (PRESERVE_REGION ? m0_req.aw.region : 4'b0), m0_req.aw.atop,
    (PRESERVE_USER ? m0_req.aw.user : '0)
  };
  wire [AW_CANON_W-1:0] m1_aw_data = {
    m1_req.aw.id[IN_ID_W-1:0], m1_req.aw.addr, m1_req.aw.len,
    m1_req.aw.size, m1_req.aw.burst, m1_req.aw.lock, m1_req.aw.cache,
    m1_req.aw.prot, m1_req.aw.qos,
    (PRESERVE_REGION ? m1_req.aw.region : 4'b0), m1_req.aw.atop,
    (PRESERVE_USER ? m1_req.aw.user : '0)
  };
  wire s_ar_valid = s_req.ar_valid &&
    decode(s_req.ar.addr) == watch_route &&
    s_req.ar.id == watch_id;
  wire s_ar_hsk = s_ar_valid && s_rsp.ar_ready;
  wire m_ar_valid = watch_route == 1 ?
    (m1_req.ar_valid &&
      m1_req.ar.id[OUT_ID_W-1] == source &&
      m1_req.ar.id[IN_ID_W-1:0] == watch_id) :
    (watch_route == 0 && m0_req.ar_valid &&
      m0_req.ar.id[OUT_ID_W-1] == source &&
      m0_req.ar.id[IN_ID_W-1:0] == watch_id);
  wire m_ar_hsk = m_ar_valid &&
    (watch_route == 1 ? m1_rsp.ar_ready : m0_rsp.ar_ready);
  wire [AR_CANON_W-1:0] s_ar_data = {
    s_req.ar.id, s_req.ar.addr, s_req.ar.len,
    s_req.ar.size, s_req.ar.burst, s_req.ar.lock,
    s_req.ar.cache, s_req.ar.prot, s_req.ar.qos,
    (PRESERVE_REGION ? s_req.ar.region : 4'b0),
    (PRESERVE_USER ? s_req.ar.user : '0)
  };
  wire [AR_CANON_W-1:0] m0_ar_data = {
    m0_req.ar.id[IN_ID_W-1:0], m0_req.ar.addr, m0_req.ar.len,
    m0_req.ar.size, m0_req.ar.burst, m0_req.ar.lock, m0_req.ar.cache,
    m0_req.ar.prot, m0_req.ar.qos,
    (PRESERVE_REGION ? m0_req.ar.region : 4'b0),
    (PRESERVE_USER ? m0_req.ar.user : '0)
  };
  wire [AR_CANON_W-1:0] m1_ar_data = {
    m1_req.ar.id[IN_ID_W-1:0], m1_req.ar.addr, m1_req.ar.len,
    m1_req.ar.size, m1_req.ar.burst, m1_req.ar.lock, m1_req.ar.cache,
    m1_req.ar.prot, m1_req.ar.qos,
    (PRESERVE_REGION ? m1_req.ar.region : 4'b0),
    (PRESERVE_USER ? m1_req.ar.user : '0)
  };
  wire [AW_CANON_W-1:0] route_s_data = watch_write ?
    s_aw_data : {{(AW_CANON_W-AR_CANON_W){1'b0}}, s_ar_data};
  wire [AW_CANON_W-1:0] route_m_data = watch_write ?
    (watch_route == 1 ? m1_aw_data : m0_aw_data) :
    {{(AW_CANON_W-AR_CANON_W){1'b0}},
      (watch_route == 1 ? m1_ar_data : m0_ar_data)};
  wire route_select_now = select_now && watch_route != DEST_ERROR;
  wire selected_route_hsk, selected_route_offer;
  wire selected_route_pending, selected_route_completed;
  fv_xbar_stream_tracker #(
    .WIDTH(AW_CANON_W), .MAX_PENDING(MAX_OUTSTANDING),
    .ALLOW_BYPASS(1'b1), .ENABLE_PROGRESS(ENABLE_PROGRESS),
    .MAX_DELAY(MAX_DELAY), .BIT_W(PAYLOAD_BIT_W)
  ) i_route (
    .clk(clk), .rstn(rstn), .select_class(watch_write),
    .select_now(route_select_now),
    .s_data(route_s_data),
    .s_valid(watch_route != DEST_ERROR &&
      (watch_write ? s_aw_valid : s_ar_valid)),
    .s_hsk(watch_route != DEST_ERROR &&
      (watch_write ? s_aw_hsk : s_ar_hsk)),
    .m_data(route_m_data),
    .m_valid(watch_write ? m_aw_valid : m_ar_valid),
    .m_hsk(watch_write ? m_aw_hsk : m_ar_hsk),
    .watch_bit(watch_payload_bit),
    .selected_m_hsk(selected_route_hsk),
    .selected_m_offer(selected_route_offer),
    .selected_pending(selected_route_pending),
    .selected_completed(selected_route_completed)
  );

  // The route choice is stable and range-constrained above.  Keep the
  // selected output pair view explicit here so the write tracker never
  // dynamically indexes a two-entry array with the decode-error value.
  wire selected_m_pair_select_aw = watch_route == 1 ?
    m1_pair_select_aw : m0_pair_select_aw;
  wire selected_m_pair_select_w = watch_route == 1 ?
    m1_pair_select_w : m0_pair_select_w;
  wire selected_m_pair_pending_aw = watch_route == 1 ?
    m1_pair_pending_aw : m0_pair_pending_aw;
  wire selected_m_pair_pending_w = watch_route == 1 ?
    m1_pair_pending_w : m0_pair_pending_w;
  wire selected_m_pair_completed = watch_route == 1 ?
    m1_pair_completed : m0_pair_completed;
  wire [OUT_STATE_W-1:0] selected_m_pair_rank = watch_route == 1 ?
    m1_pair_rank : m0_pair_rank;
  wire [7:0] selected_m_pair_watch_beat = watch_route == 1 ?
    m1_pair_watch_beat : m0_pair_watch_beat;
  wire [W_PAYLOAD_BIT_W-1:0] selected_m_pair_w_payload_idx =
    watch_route == 1 ? m1_pair_w_payload_idx : m0_pair_w_payload_idx;
  wire selected_m_pair_w_payload_bit = watch_route == 1 ?
    m1_pair_w_payload_bit : m0_pair_w_payload_bit;
  wire selected_m_pair_w_payload_available = watch_route == 1 ?
    m1_pair_w_payload_available : m0_pair_w_payload_available;

  fv_xbar_read_tracker #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .IN_ID_W(IN_ID_W), .OUT_ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_OUTPUT_OUTSTANDING(MAX_OUTPUT_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_OUTPUT_AW_AHEAD(MAX_OUTPUT_AW_AHEAD),
    .MAX_OUTPUT_W_AHEAD(MAX_OUTPUT_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_PROGRESS(ENABLE_PROGRESS), .MAX_DELAY(MAX_DELAY),
    .ADDR0_BASE(ADDR0_BASE), .ADDR1_BASE(ADDR1_BASE), .ADDR_MASK(ADDR_MASK),
    .DEFAULT_ENABLE(DEFAULT_ENABLE), .DEFAULT_DEST(DEFAULT_DEST),
    .PRESERVE_USER(PRESERVE_USER),
    .ERROR_RDATA(ERROR_RDATA), .PAYLOAD_BIT_W(PAYLOAD_BIT_W)
  ) i_read (
    .clk(clk), .rstn(rstn), .enable(!watch_write), .source(source),
    .watch_route(watch_route), .watch_id(watch_id), .watch_beat(watch_beat),
    .watch_payload_bit(watch_payload_bit),
    .role_selected(role_selected && !watch_write),
    .s_protocol_pending(s_rd_pending),
    .s_protocol_completed(s_rd_completed),
    .s_protocol_rank(s_rd_rank), .s_protocol_beat(s_rd_rsp_beat),
    .s_protocol_rsp_visible(s_rd_rsp_visible),
    .m_protocol_outstanding(watch_route == 1 ?
      m1_rd_outstanding : m0_rd_outstanding),
    .route_hsk(selected_route_hsk && !watch_write),
    .select_now(select_now && !watch_write),
    .s_req_bits(s_req_bits), .s_rsp_bits(s_rsp_bits),
    .m0_req_bits(m0_req_bits), .m0_rsp_bits(m0_rsp_bits),
    .m1_req_bits(m1_req_bits), .m1_rsp_bits(m1_rsp_bits)
  );

  fv_xbar_write_tracker #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .IN_ID_W(IN_ID_W), .OUT_ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_OUTPUT_OUTSTANDING(MAX_OUTPUT_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_OUTPUT_AW_AHEAD(MAX_OUTPUT_AW_AHEAD),
    .MAX_OUTPUT_W_AHEAD(MAX_OUTPUT_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_PROGRESS(ENABLE_PROGRESS), .MAX_DELAY(MAX_DELAY),
    .ADDR0_BASE(ADDR0_BASE), .ADDR1_BASE(ADDR1_BASE), .ADDR_MASK(ADDR_MASK),
    .DEFAULT_ENABLE(DEFAULT_ENABLE), .DEFAULT_DEST(DEFAULT_DEST),
    .PRESERVE_USER(PRESERVE_USER), .PAYLOAD_BIT_W(PAYLOAD_BIT_W)
  ) i_write (
    .clk(clk), .rstn(rstn), .enable(watch_write), .source(source),
    .watch_route(watch_route), .watch_id(watch_id), .watch_beat(watch_beat),
    .watch_payload_bit(watch_payload_bit),
    .role_selected(role_selected && watch_write),
    .s_protocol_pending(s_wr_pending),
    .s_protocol_completed(s_wr_completed), .s_protocol_rank(s_wr_rank),
    .s_protocol_w_pending(s_wr_data_pending),
    .s_protocol_w_rank(s_wr_data_rank),
    .s_protocol_w_complete(s_wr_data_complete),
    .s_protocol_rsp_visible(s_wr_rsp_visible),
    .m_protocol_outstanding(watch_route == 1 ?
      m1_wr_outstanding : m0_wr_outstanding),
    .m_protocol_wr_select(selected_m_wr_select),
    .m_protocol_wr_selected(selected_m_wr_selected),
    .m_protocol_wr_completed(selected_m_wr_completed),
    .m_protocol_wr_rsp_visible(selected_m_wr_rsp_visible),
    .m_protocol_wr_b_bits(selected_m_wr_b_bits),
    .route_hsk(selected_route_hsk && watch_write),
    .route_offer(selected_route_offer && watch_write),
    .route_pending(selected_route_pending && watch_write),
    .route_completed(selected_route_completed && watch_write),
    .s_pair_skew(s_pair_skew),
    .m0_pair_skew(m0_pair_skew), .m1_pair_skew(m1_pair_skew),
    .s_pair_select_aw(s_pair_select_aw),
    .s_pair_pending_aw(s_pair_pending_aw),
    .s_pair_pending_w(s_pair_pending_w),
    .s_pair_completed(s_pair_completed),
    .s_pair_rank(s_pair_rank),
    .s_pair_w_payload_idx(s_pair_w_payload_idx),
    .s_pair_w_payload_bit(s_pair_w_payload_bit),
    .s_pair_w_payload_available(s_pair_w_payload_available),
    .m_pair_select_aw(selected_m_pair_select_aw),
    .m_pair_select_w(selected_m_pair_select_w),
    .m_pair_pending_aw(selected_m_pair_pending_aw),
    .m_pair_pending_w(selected_m_pair_pending_w),
    .m_pair_completed(selected_m_pair_completed),
    .m_pair_rank(selected_m_pair_rank),
    .m_pair_watch_beat(selected_m_pair_watch_beat),
    .m_pair_w_payload_idx(selected_m_pair_w_payload_idx),
    .m_pair_w_payload_bit(selected_m_pair_w_payload_bit),
    .m_pair_w_payload_available(selected_m_pair_w_payload_available),
    .s_channel_w_beat(s_channel_w_beat),
    .m0_channel_w_beat(m0_channel_w_beat),
    .m1_channel_w_beat(m1_channel_w_beat),
    .select_now(select_now && watch_write),
    .s_req_bits(s_req_bits), .s_rsp_bits(s_rsp_bits),
    .m0_req_bits(m0_req_bits), .m0_rsp_bits(m0_rsp_bits),
    .m1_req_bits(m1_req_bits), .m1_rsp_bits(m1_rsp_bits)
  );
endmodule


// 2x2 crossbar functionality only.  All ports are public endpoint views and
// every interface is explicit to avoid tool-dependent unpacked-array binding.
module fv_axi_xbar_role_fvip #(
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
  parameter bit PREFIX_SOURCE_ID = 1'b1,
  parameter bit PRESERVE_REGION = 1'b1,
  parameter bit PRESERVE_USER = 1'b1,
  parameter logic [DATA_W-1:0] ERROR_RDATA = DATA_W'(64'hca11_ab1e_bad_cab1e)
) (
  input logic clk,
  input logic rstn,
  axi_fvip_txn_view_if.Consumer s0_view,
  axi_fvip_txn_view_if.Consumer s1_view,
  axi_fvip_txn_view_if.Consumer m0_view,
  axi_fvip_txn_view_if.Consumer m1_view
);
  localparam int IN_AW_W = IN_ID_W + ADDR_W + 35 + USER_W;
  localparam int IN_W_W = DATA_W + DATA_W/8 + 1 + USER_W;
  localparam int IN_AR_W = IN_ID_W + ADDR_W + 29 + USER_W;
  localparam int IN_B_W = IN_ID_W + 2 + USER_W;
  localparam int IN_R_W = IN_ID_W + DATA_W + 3 + USER_W;
  localparam int IN_REQ_W = IN_AW_W + IN_W_W + IN_AR_W + 5;
  localparam int IN_RSP_W = IN_B_W + IN_R_W + 5;
  localparam int OUT_AW_W = OUT_ID_W + ADDR_W + 35 + USER_W;
  localparam int OUT_W_W = IN_W_W;
  localparam int OUT_AR_W = OUT_ID_W + ADDR_W + 29 + USER_W;
  localparam int OUT_B_W = OUT_ID_W + 2 + USER_W;
  localparam int OUT_R_W = OUT_ID_W + DATA_W + 3 + USER_W;
  localparam int OUT_REQ_W = OUT_AW_W + OUT_W_W + OUT_AR_W + 5;
  localparam int OUT_RSP_W = OUT_B_W + OUT_R_W + 5;
  localparam int IN_PAIR_MAX =
    (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD;
  localparam int IN_PAIR_SKEW_W = $clog2(IN_PAIR_MAX + 1) + 1;
  localparam int IN_STATE_MAX =
    MAX_OUTSTANDING + MAX_AW_AHEAD + MAX_W_AHEAD;
  localparam int IN_STATE_W =
    (IN_STATE_MAX < 2) ? 1 : $clog2(IN_STATE_MAX + 1);
  localparam int OUT_STATE_MAX =
    MAX_OUTPUT_OUTSTANDING + MAX_OUTPUT_AW_AHEAD + MAX_OUTPUT_W_AHEAD;
  localparam int OUT_STATE_W =
    (OUT_STATE_MAX < 2) ? 1 : $clog2(OUT_STATE_MAX + 1);
  localparam int W_BEAT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1);
  localparam int W_PAYLOAD_BIT_W = (IN_W_W < 2) ? 1 : $clog2(IN_W_W);

  wire [IN_REQ_W-1:0] s0_req_bits = {
    s0_view.live_aw, s0_view.live_aw_valid,
    s0_view.live_w, s0_view.live_w_valid, s0_view.live_b_ready,
    s0_view.live_ar, s0_view.live_ar_valid, s0_view.live_r_ready
  };
  wire [IN_RSP_W-1:0] s0_rsp_bits = {
    s0_view.live_aw_ready, s0_view.live_ar_ready, s0_view.live_w_ready,
    s0_view.live_b_valid, s0_view.live_b,
    s0_view.live_r_valid, s0_view.live_r
  };
  wire [IN_REQ_W-1:0] s1_req_bits = {
    s1_view.live_aw, s1_view.live_aw_valid,
    s1_view.live_w, s1_view.live_w_valid, s1_view.live_b_ready,
    s1_view.live_ar, s1_view.live_ar_valid, s1_view.live_r_ready
  };
  wire [IN_RSP_W-1:0] s1_rsp_bits = {
    s1_view.live_aw_ready, s1_view.live_ar_ready, s1_view.live_w_ready,
    s1_view.live_b_valid, s1_view.live_b,
    s1_view.live_r_valid, s1_view.live_r
  };
  wire [OUT_REQ_W-1:0] m0_req_bits = {
    m0_view.live_aw, m0_view.live_aw_valid,
    m0_view.live_w, m0_view.live_w_valid, m0_view.live_b_ready,
    m0_view.live_ar, m0_view.live_ar_valid, m0_view.live_r_ready
  };
  wire [OUT_RSP_W-1:0] m0_rsp_bits = {
    m0_view.live_aw_ready, m0_view.live_ar_ready, m0_view.live_w_ready,
    m0_view.live_b_valid, m0_view.live_b,
    m0_view.live_r_valid, m0_view.live_r
  };
  wire [OUT_REQ_W-1:0] m1_req_bits = {
    m1_view.live_aw, m1_view.live_aw_valid,
    m1_view.live_w, m1_view.live_w_valid, m1_view.live_b_ready,
    m1_view.live_ar, m1_view.live_ar_valid, m1_view.live_r_ready
  };
  wire [OUT_RSP_W-1:0] m1_rsp_bits = {
    m1_view.live_aw_ready, m1_view.live_ar_ready, m1_view.live_w_ready,
    m1_view.live_b_valid, m1_view.live_b,
    m1_view.live_r_valid, m1_view.live_r
  };

  wire [ADDR_W-1:0] s0_aw_addr =
    s0_view.live_aw[IN_AW_W-IN_ID_W-1 -: ADDR_W];
  wire [ADDR_W-1:0] s1_aw_addr =
    s1_view.live_aw[IN_AW_W-IN_ID_W-1 -: ADDR_W];
  wire [ADDR_W-1:0] s0_ar_addr =
    s0_view.live_ar[IN_AR_W-IN_ID_W-1 -: ADDR_W];
  wire [ADDR_W-1:0] s1_ar_addr =
    s1_view.live_ar[IN_AR_W-IN_ID_W-1 -: ADDR_W];
  wire [OUT_ID_W-1:0] m0_r_id = m0_view.live_r[OUT_R_W-1 -: OUT_ID_W];
  wire m0_r_hsk = m0_view.live_r_valid && m0_view.live_r_ready;

  function automatic logic [1:0] decode(
    input logic [ADDR_W-1:0] addr, input int source);
    if ((addr & ADDR_MASK) == ADDR0_BASE)
      decode = 2'd0;
    else if ((addr & ADDR_MASK) == ADDR1_BASE)
      decode = 2'd1;
    else if (DEFAULT_ENABLE[source])
      decode = DEFAULT_DEST[source] ? 2'd1 : 2'd0;
    else
      decode = 2'd2;
  endfunction

  a_prefix_configuration: assert property (@(posedge clk)
    PREFIX_SOURCE_ID && OUT_ID_W == IN_ID_W + 1);
  a_nonoverlap_configuration: assert property (@(posedge clk)
    (ADDR0_BASE & ADDR_MASK) != (ADDR1_BASE & ADDR_MASK));
  (* anyconst *) logic watch_source;
  s_watch_source_constant: assume property (@(posedge clk)
    disable iff ($isunknown(rstn)) $stable(watch_source));

  wire [IN_REQ_W-1:0] selected_s_req_bits =
    watch_source ? s1_req_bits : s0_req_bits;
  wire [IN_RSP_W-1:0] selected_s_rsp_bits =
    watch_source ? s1_rsp_bits : s0_rsp_bits;
  wire signed [IN_PAIR_SKEW_W-1:0] selected_s_pair_skew =
    watch_source ? s1_view.pair_skew : s0_view.pair_skew;
  wire selected_s_pair_select_aw =
    watch_source ? s1_view.pair_select_aw : s0_view.pair_select_aw;
  wire selected_s_pair_pending_aw =
    watch_source ? s1_view.pair_pending_aw : s0_view.pair_pending_aw;
  wire selected_s_pair_pending_w =
    watch_source ? s1_view.pair_pending_w : s0_view.pair_pending_w;
  wire selected_s_pair_completed =
    watch_source ? s1_view.pair_completed : s0_view.pair_completed;
  wire [IN_STATE_W-1:0] selected_s_pair_rank =
    watch_source ? s1_view.pair_rank : s0_view.pair_rank;
  wire [W_PAYLOAD_BIT_W-1:0] selected_s_pair_w_payload_idx =
    watch_source ?
      s1_view.pair_w_payload_idx : s0_view.pair_w_payload_idx;
  wire selected_s_pair_w_payload_bit =
    watch_source ?
      s1_view.pair_w_payload_bit : s0_view.pair_w_payload_bit;
  wire selected_s_pair_w_payload_available =
    watch_source ?
      s1_view.pair_w_payload_available : s0_view.pair_w_payload_available;
  wire [W_BEAT_W-1:0] selected_s_channel_w_beat =
    watch_source ? s1_view.channel_w_beat : s0_view.channel_w_beat;
  wire selected_s_rd_select =
    watch_source ? s1_view.rd_select : s0_view.rd_select;
  wire [IN_ID_W-1:0] selected_s_rd_watch_id =
    watch_source ? s1_view.rd_watch_id : s0_view.rd_watch_id;
  wire [7:0] selected_s_rd_watch_beat =
    watch_source ? s1_view.rd_beat_idx : s0_view.rd_beat_idx;
  wire selected_s_rd_pending =
    watch_source ? s1_view.rd_pending : s0_view.rd_pending;
  wire selected_s_rd_completed =
    watch_source ? s1_view.rd_completed : s0_view.rd_completed;
  wire [IN_STATE_W-1:0] selected_s_rd_rank =
    watch_source ? s1_view.rd_rank : s0_view.rd_rank;
  wire [7:0] selected_s_rd_rsp_beat =
    watch_source ? s1_view.rd_rsp_beat : s0_view.rd_rsp_beat;
  wire selected_s_rd_rsp_visible =
    watch_source ? s1_view.rd_rsp_visible : s0_view.rd_rsp_visible;
  wire selected_s_wr_select =
    watch_source ? s1_view.wr_select : s0_view.wr_select;
  wire [IN_ID_W-1:0] selected_s_wr_watch_id =
    watch_source ? s1_view.wr_watch_id : s0_view.wr_watch_id;
  wire [7:0] selected_s_wr_watch_beat =
    watch_source ? s1_view.wr_beat_idx : s0_view.wr_beat_idx;
  wire selected_s_wr_pending =
    watch_source ? s1_view.wr_pending : s0_view.wr_pending;
  wire selected_s_wr_completed =
    watch_source ? s1_view.wr_completed : s0_view.wr_completed;
  wire [IN_STATE_W-1:0] selected_s_wr_rank =
    watch_source ? s1_view.wr_rank : s0_view.wr_rank;
  wire selected_s_wr_data_pending =
    watch_source ? s1_view.wr_data_pending : s0_view.wr_data_pending;
  wire [IN_STATE_W-1:0] selected_s_wr_data_rank =
    watch_source ? s1_view.wr_data_rank : s0_view.wr_data_rank;
  wire selected_s_wr_data_complete =
    watch_source ? s1_view.wr_data_complete : s0_view.wr_data_complete;
  wire selected_s_wr_rsp_visible =
    watch_source ? s1_view.wr_rsp_visible : s0_view.wr_rsp_visible;

  fv_axi_xbar_source_role #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .IN_ID_W(IN_ID_W), .OUT_ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_OUTPUT_OUTSTANDING(MAX_OUTPUT_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_OUTPUT_AW_AHEAD(MAX_OUTPUT_AW_AHEAD),
    .MAX_OUTPUT_W_AHEAD(MAX_OUTPUT_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_PROGRESS(ENABLE_PROGRESS), .MAX_DELAY(MAX_DELAY),
    .ADDR0_BASE(ADDR0_BASE), .ADDR1_BASE(ADDR1_BASE), .ADDR_MASK(ADDR_MASK),
    .DEFAULT_ENABLE(DEFAULT_ENABLE), .DEFAULT_DEST(DEFAULT_DEST),
    .PRESERVE_REGION(PRESERVE_REGION), .PRESERVE_USER(PRESERVE_USER),
    .ERROR_RDATA(ERROR_RDATA)
  ) i_source (
    .clk(clk), .rstn(rstn), .source(watch_source),
    .s_pair_skew(selected_s_pair_skew),
    .m0_pair_skew(m0_view.pair_skew), .m1_pair_skew(m1_view.pair_skew),
    .s_pair_select_aw(selected_s_pair_select_aw),
    .s_pair_pending_aw(selected_s_pair_pending_aw),
    .s_pair_pending_w(selected_s_pair_pending_w),
    .s_pair_completed(selected_s_pair_completed),
    .s_pair_rank(selected_s_pair_rank),
    .s_pair_w_payload_idx(selected_s_pair_w_payload_idx),
    .s_pair_w_payload_bit(selected_s_pair_w_payload_bit),
    .s_pair_w_payload_available(selected_s_pair_w_payload_available),
    .m0_pair_select_aw(m0_view.pair_select_aw),
    .m1_pair_select_aw(m1_view.pair_select_aw),
    .m0_pair_select_w(m0_view.pair_select_w),
    .m1_pair_select_w(m1_view.pair_select_w),
    .m0_pair_pending_aw(m0_view.pair_pending_aw),
    .m1_pair_pending_aw(m1_view.pair_pending_aw),
    .m0_pair_pending_w(m0_view.pair_pending_w),
    .m1_pair_pending_w(m1_view.pair_pending_w),
    .m0_pair_completed(m0_view.pair_completed),
    .m1_pair_completed(m1_view.pair_completed),
    .m0_pair_rank(m0_view.pair_rank),
    .m1_pair_rank(m1_view.pair_rank),
    .m0_pair_watch_beat(m0_view.wr_beat_idx),
    .m1_pair_watch_beat(m1_view.wr_beat_idx),
    .m0_pair_w_payload_idx(m0_view.pair_w_payload_idx),
    .m1_pair_w_payload_idx(m1_view.pair_w_payload_idx),
    .m0_pair_w_payload_bit(m0_view.pair_w_payload_bit),
    .m1_pair_w_payload_bit(m1_view.pair_w_payload_bit),
    .m0_pair_w_payload_available(m0_view.pair_w_payload_available),
    .m1_pair_w_payload_available(m1_view.pair_w_payload_available),
    .s_channel_w_beat(selected_s_channel_w_beat),
    .m0_channel_w_beat(m0_view.channel_w_beat),
    .m1_channel_w_beat(m1_view.channel_w_beat),
    .s_rd_select(selected_s_rd_select),
    .s_rd_watch_id(selected_s_rd_watch_id),
    .s_rd_watch_beat(selected_s_rd_watch_beat),
    .s_rd_pending(selected_s_rd_pending),
    .s_rd_completed(selected_s_rd_completed),
    .s_rd_rank(selected_s_rd_rank),
    .s_rd_rsp_beat(selected_s_rd_rsp_beat),
    .s_rd_rsp_visible(selected_s_rd_rsp_visible),
    .s_wr_select(selected_s_wr_select),
    .s_wr_watch_id(selected_s_wr_watch_id),
    .s_wr_watch_beat(selected_s_wr_watch_beat),
    .s_wr_pending(selected_s_wr_pending),
    .s_wr_completed(selected_s_wr_completed),
    .s_wr_rank(selected_s_wr_rank),
    .s_wr_data_pending(selected_s_wr_data_pending),
    .s_wr_data_rank(selected_s_wr_data_rank),
    .s_wr_data_complete(selected_s_wr_data_complete),
    .s_wr_rsp_visible(selected_s_wr_rsp_visible),
    .m0_rd_watch_id(m0_view.rd_watch_id),
    .m1_rd_watch_id(m1_view.rd_watch_id),
    .m0_rd_outstanding(m0_view.rd_outstanding),
    .m1_rd_outstanding(m1_view.rd_outstanding),
    .m0_wr_watch_id(m0_view.wr_watch_id),
    .m1_wr_watch_id(m1_view.wr_watch_id),
    .m0_wr_outstanding(m0_view.wr_outstanding),
    .m1_wr_outstanding(m1_view.wr_outstanding),
    .m0_wr_select(m0_view.wr_select),
    .m1_wr_select(m1_view.wr_select),
    .m0_wr_selected(m0_view.wr_selected),
    .m1_wr_selected(m1_view.wr_selected),
    .m0_wr_completed(m0_view.wr_completed),
    .m1_wr_completed(m1_view.wr_completed),
    .m0_wr_rsp_visible(m0_view.wr_rsp_visible),
    .m1_wr_rsp_visible(m1_view.wr_rsp_visible),
    .m0_wr_b_bits({
      m0_view.wr_b.id, m0_view.wr_b.resp, m0_view.wr_b.user}),
    .m1_wr_b_bits({
      m1_view.wr_b.id, m1_view.wr_b.resp, m1_view.wr_b.user}),
    .s_req_bits(selected_s_req_bits), .s_rsp_bits(selected_s_rsp_bits),
    .m0_req_bits(m0_req_bits), .m0_rsp_bits(m0_rsp_bits),
    .m1_req_bits(m1_req_bits), .m1_rsp_bits(m1_rsp_bits)
  );

  c_aw_contention: cover property (@(posedge clk) disable iff (!rstn)
    s0_view.live_aw_valid && s1_view.live_aw_valid &&
    decode(s0_aw_addr, 0) == 0 && decode(s1_aw_addr, 1) == 0);
  c_ar_independent_destinations: cover property (@(posedge clk) disable iff (!rstn)
    s0_view.live_ar_valid && s1_view.live_ar_valid &&
    decode(s0_ar_addr, 0) == 0 && decode(s1_ar_addr, 1) == 1);
  c_decode_error: cover property (@(posedge clk) disable iff (!rstn)
    s0_view.live_ar_valid && s0_view.live_ar_ready &&
    decode(s0_ar_addr, 0) == 2);
  c_output_backpressure: cover property (@(posedge clk) disable iff (!rstn)
    (m0_view.live_aw_valid && !m0_view.live_aw_ready) ||
    (m1_view.live_ar_valid && !m1_view.live_ar_ready));
  c_different_id_reordering: cover property (@(posedge clk) disable iff (!rstn)
    m0_r_hsk && !m0_view.live_r[USER_W] ##[1:8]
    m0_r_hsk && m0_r_id != $past(m0_r_id));
endmodule
