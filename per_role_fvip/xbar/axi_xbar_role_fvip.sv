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
  parameter logic [DATA_W-1:0] ERROR_RDATA = DATA_W'(64'hca11_ab1e_bad_cab1e)
) (
  input logic clk,
  input logic rstn,
  input logic source,
  axi_fvip_txn_view_if.Consumer s0_view,
  axi_fvip_txn_view_if.Consumer s1_view,
  axi_fvip_txn_view_if.Consumer m0_view,
  axi_fvip_txn_view_if.Consumer m1_view
);
  localparam int AW_CANON_W = axi_pkg::aw_width(ADDR_W, IN_ID_W, USER_W);
  localparam int AR_CANON_W = axi_pkg::ar_width(ADDR_W, IN_ID_W, USER_W);
  localparam int R_CANON_W = axi_pkg::r_width(DATA_W, IN_ID_W, USER_W);
  localparam int W_CANON_W = axi_pkg::w_width(DATA_W, USER_W);
  localparam int B_CANON_W = axi_pkg::b_width(IN_ID_W, USER_W);
  localparam int ROLE_PAYLOAD_W0 =
    (AW_CANON_W > R_CANON_W) ? AW_CANON_W : R_CANON_W;
  localparam int ROLE_PAYLOAD_W1 =
    (W_CANON_W > B_CANON_W) ? W_CANON_W : B_CANON_W;
  localparam int ROLE_PAYLOAD_W =
    (ROLE_PAYLOAD_W0 > ROLE_PAYLOAD_W1) ?
      ROLE_PAYLOAD_W0 : ROLE_PAYLOAD_W1;
  localparam int PAYLOAD_BIT_W =
    (ROLE_PAYLOAD_W < 2) ? 1 : $clog2(ROLE_PAYLOAD_W);
  localparam logic [1:0] DEST_ERROR = 2'd2;

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [USER_W-1:0] user_t;
  typedef logic [IN_ID_W-1:0] in_id_t;
  typedef logic [OUT_ID_W-1:0] out_id_t;
  `AXI_TYPEDEF_AW_CHAN_T(in_aw_t, addr_t, in_id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(in_ar_t, addr_t, in_id_t, user_t)
  `AXI_TYPEDEF_AW_CHAN_T(out_aw_t, addr_t, out_id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(out_ar_t, addr_t, out_id_t, user_t)
  in_aw_t s_aw;
  in_ar_t s_ar;
  out_aw_t m0_aw, m1_aw;
  out_ar_t m0_ar, m1_ar;
  assign s_aw = source ? s1_view.live_aw : s0_view.live_aw;
  assign s_ar = source ? s1_view.live_ar : s0_view.live_ar;
  assign m0_aw = m0_view.live_aw;
  assign m1_aw = m1_view.live_aw;
  assign m0_ar = m0_view.live_ar;
  assign m1_ar = m1_view.live_ar;

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
  wire selected_s_rd_select = source ? s1_view.rd_select : s0_view.rd_select;
  wire selected_s_wr_select = source ? s1_view.wr_select : s0_view.wr_select;
  wire [IN_ID_W-1:0] selected_s_rd_watch_id =
    source ? s1_view.rd_watch_id : s0_view.rd_watch_id;
  wire [IN_ID_W-1:0] selected_s_wr_watch_id =
    source ? s1_view.wr_watch_id : s0_view.wr_watch_id;
  wire [IN_ID_W-1:0] watch_id =
    watch_write ? selected_s_wr_watch_id : selected_s_rd_watch_id;
  wire [OUT_ID_W-1:0] selected_m_watch_id = watch_write ?
    (watch_route == 1 ? m1_view.wr_watch_id : m0_view.wr_watch_id) :
    (watch_route == 1 ? m1_view.rd_watch_id : m0_view.rd_watch_id);
  wire output_watch_matches = watch_route == DEST_ERROR ||
    selected_m_watch_id == {source, watch_id};
  wire selected_input_hsk = watch_write ?
    (selected_s_wr_select && decode(s_aw.addr) == watch_route &&
      output_watch_matches) :
    (selected_s_rd_select && decode(s_ar.addr) == watch_route &&
      output_watch_matches);
  logic role_selected;
  wire select_now = selected_input_hsk && !role_selected;
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn)
      role_selected <= 1'b0;
    else if (select_now)
      role_selected <= 1'b1;
  end

  wire s_aw_valid =
    (source ? s1_view.live_aw_valid : s0_view.live_aw_valid) &&
    decode(s_aw.addr) == watch_route && s_aw.id == watch_id;
  wire s_aw_hsk = s_aw_valid &&
    (source ? s1_view.live_aw_ready : s0_view.live_aw_ready);
  wire m_aw_valid = watch_route == 1 ?
    (m1_view.live_aw_valid && m1_aw.id[OUT_ID_W-1] == source &&
      m1_aw.id[IN_ID_W-1:0] == watch_id) :
    (watch_route == 0 && m0_view.live_aw_valid &&
      m0_aw.id[OUT_ID_W-1] == source &&
      m0_aw.id[IN_ID_W-1:0] == watch_id);
  wire m_aw_hsk = m_aw_valid &&
    (watch_route == 1 ? m1_view.live_aw_ready : m0_view.live_aw_ready);
  wire [AW_CANON_W-1:0] s_aw_data = {
    s_aw.id, s_aw.addr, s_aw.len, s_aw.size, s_aw.burst, s_aw.lock,
    s_aw.cache, s_aw.prot, s_aw.qos,
    (PRESERVE_REGION ? s_aw.region : 4'b0),
    s_aw.atop, (PRESERVE_USER ? s_aw.user : '0)
  };
  wire [AW_CANON_W-1:0] m0_aw_data = {
    m0_aw.id[IN_ID_W-1:0], m0_aw.addr, m0_aw.len,
    m0_aw.size, m0_aw.burst, m0_aw.lock, m0_aw.cache,
    m0_aw.prot, m0_aw.qos,
    (PRESERVE_REGION ? m0_aw.region : 4'b0), m0_aw.atop,
    (PRESERVE_USER ? m0_aw.user : '0)
  };
  wire [AW_CANON_W-1:0] m1_aw_data = {
    m1_aw.id[IN_ID_W-1:0], m1_aw.addr, m1_aw.len,
    m1_aw.size, m1_aw.burst, m1_aw.lock, m1_aw.cache,
    m1_aw.prot, m1_aw.qos,
    (PRESERVE_REGION ? m1_aw.region : 4'b0), m1_aw.atop,
    (PRESERVE_USER ? m1_aw.user : '0)
  };
  wire s_ar_valid =
    (source ? s1_view.live_ar_valid : s0_view.live_ar_valid) &&
    decode(s_ar.addr) == watch_route && s_ar.id == watch_id;
  wire s_ar_hsk = s_ar_valid &&
    (source ? s1_view.live_ar_ready : s0_view.live_ar_ready);
  wire m_ar_valid = watch_route == 1 ?
    (m1_view.live_ar_valid && m1_ar.id[OUT_ID_W-1] == source &&
      m1_ar.id[IN_ID_W-1:0] == watch_id) :
    (watch_route == 0 && m0_view.live_ar_valid &&
      m0_ar.id[OUT_ID_W-1] == source &&
      m0_ar.id[IN_ID_W-1:0] == watch_id);
  wire m_ar_hsk = m_ar_valid &&
    (watch_route == 1 ? m1_view.live_ar_ready : m0_view.live_ar_ready);
  wire [AR_CANON_W-1:0] s_ar_data = {
    s_ar.id, s_ar.addr, s_ar.len, s_ar.size, s_ar.burst, s_ar.lock,
    s_ar.cache, s_ar.prot, s_ar.qos,
    (PRESERVE_REGION ? s_ar.region : 4'b0),
    (PRESERVE_USER ? s_ar.user : '0)
  };
  wire [AR_CANON_W-1:0] m0_ar_data = {
    m0_ar.id[IN_ID_W-1:0], m0_ar.addr, m0_ar.len,
    m0_ar.size, m0_ar.burst, m0_ar.lock, m0_ar.cache,
    m0_ar.prot, m0_ar.qos, (PRESERVE_REGION ? m0_ar.region : 4'b0),
    (PRESERVE_USER ? m0_ar.user : '0)
  };
  wire [AR_CANON_W-1:0] m1_ar_data = {
    m1_ar.id[IN_ID_W-1:0], m1_ar.addr, m1_ar.len,
    m1_ar.size, m1_ar.burst, m1_ar.lock, m1_ar.cache,
    m1_ar.prot, m1_ar.qos, (PRESERVE_REGION ? m1_ar.region : 4'b0),
    (PRESERVE_USER ? m1_ar.user : '0)
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

  fv_xbar_read_tracker #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .IN_ID_W(IN_ID_W), .OUT_ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_OUTPUT_OUTSTANDING(MAX_OUTPUT_OUTSTANDING),
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
    .watch_route(watch_route), .watch_payload_bit(watch_payload_bit),
    .role_selected(role_selected && !watch_write),
    .route_hsk(selected_route_hsk && !watch_write),
    .select_now(select_now && !watch_write),
    .s0_view(s0_view), .s1_view(s1_view),
    .m0_view(m0_view), .m1_view(m1_view)
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
    .watch_route(watch_route), .watch_payload_bit(watch_payload_bit),
    .role_selected(role_selected && watch_write),
    .route_hsk(selected_route_hsk && watch_write),
    .route_offer(selected_route_offer && watch_write),
    .route_pending(selected_route_pending && watch_write),
    .route_completed(selected_route_completed && watch_write),
    .select_now(select_now && watch_write),
    .s0_view(s0_view), .s1_view(s1_view),
    .m0_view(m0_view), .m1_view(m1_view)
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
  localparam int IN_AW_W = axi_pkg::aw_width(ADDR_W, IN_ID_W, USER_W);
  localparam int IN_AR_W = axi_pkg::ar_width(ADDR_W, IN_ID_W, USER_W);
  localparam int OUT_R_W = axi_pkg::r_width(DATA_W, OUT_ID_W, USER_W);

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
    .s0_view(s0_view), .s1_view(s1_view),
    .m0_view(m0_view), .m1_view(m1_view)
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
