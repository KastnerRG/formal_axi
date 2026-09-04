// Select one AW occurrence, wait for its globally ordered W packet, then for
// its same-ID B response. Generic occurrence state handles response order;
// this shell adds only the W distance and universal completed-write credit.
module `MODNAME_WRITE_TRACKER #(
  parameter int ID_W = 4,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 8,
  parameter int MAX_W_AHEAD = 8,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  localparam int SKEW_W = $clog2(((MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD) + 1) + 1
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

  localparam int COUNT_W = (MAX_OUTSTANDING < 2) ? 1 : $clog2(MAX_OUTSTANDING + 1);
  localparam int PAIR_MAX = (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD;
  localparam int PAIR_W = (PAIR_MAX < 2) ? 1 : $clog2(PAIR_MAX + 1);
  localparam int AGE_W = (MAX_RESPONSE_DELAY < 2) ? 1 : $clog2(MAX_RESPONSE_DELAY + 1);
  localparam int CREDIT_MAX = (MAX_AW_AHEAD > MAX_OUTSTANDING) ? MAX_AW_AHEAD : MAX_OUTSTANDING;
  localparam int CREDIT_W = (CREDIT_MAX < 2) ? 1 : $clog2(CREDIT_MAX + 1);
  localparam int CREDIT_EXT_W = CREDIT_W + 1;

  (* anyseq *) logic select_now;
  logic selected;
  wire pending, completed;
  wire [COUNT_W-1:0] b_rank, outstanding;

  // Inclusive number of completed W packets still required by the selected
  // AW. Zero means its data is complete; the public rank is distance - 1.
  logic [SKEW_W-1:0] w_dist;
  wire w_pending = selected && w_dist != 0;
  wire [PAIR_W-1:0] w_rank = w_pending ? PAIR_W'(w_dist - SKEW_W'(1)) : '0;
  wire wr_data_complete = selected && w_dist == 0;

  wire aw_watch = aw_hsk && aw_id == watch_id;
  wire b_watch = b_valid && b_id == watch_id;
  wire b_watch_hsk = b_hsk && b_id == watch_id;
  wire rsp_eligible = pending && wr_data_complete && b_rank == 0;
  wire rsp_visible = rsp_eligible && b_watch;
  wire b_stalled = b_valid && !b_hsk;

  // The occurrence core tracks AW->B directly at depth one. At greater depth
  // it tracks completed-write credits -> B: selection is delayed until the
  // chosen AW's W packet completes, while occupancy is exposed as its live
  // predecessor rank before that point. This is the same smart tracker, with
  // the source event placed where a B first becomes legal.
  wire response_source, response_select, accepted_b;
  logic response_pending;
  logic [COUNT_W-1:0] response_rank, response_occupancy;

`ifdef AXI_FVIP_MANAGER
  logic [AGE_W-1:0] rsp_age;
  wire [CREDIT_EXT_W-1:0] watch_completed_credit;

  generate if (MAX_OUTSTANDING == 1) begin : g_single_write_credit
    wire tracked_aw = aw_watch && (response_occupancy < MAX_OUTSTANDING || accepted_b);
    assign watch_completed_credit = response_occupancy != 0 && skew <= 0 ? CREDIT_EXT_W'(response_occupancy) : '0;
    assign accepted_b = b_watch_hsk && watch_completed_credit != 0;
    assign response_source = tracked_aw;
    assign response_select = select_now;
    assign outstanding = response_occupancy;
    assign b_rank = response_rank;
  end else begin : g_per_id_write_credit
    localparam int TAG_DEPTH = (MAX_AW_AHEAD < 1) ? 1 : MAX_AW_AHEAD;
    logic [TAG_DEPTH-1:0] aw_watch_q;
    logic [CREDIT_W-1:0] watch_unpaired;
    wire [SKEW_W-1:0] positive_skew = skew > 0 ? $unsigned(skew) : '0;
    wire tag_pop = w_complete && skew > 0;
    wire tag_push = aw_hsk && (skew > 0 || (skew == 0 && !w_complete));
    wire [SKEW_W-1:0] tag_append_index = positive_skew - SKEW_W'(tag_pop);
    wire watch_credit_inc = (tag_pop && aw_watch_q[0]) || (aw_watch && (skew < 0 || (skew == 0 && w_complete)));
    wire credit_has_room = response_occupancy < MAX_OUTSTANDING || accepted_b;

    always_comb begin
      watch_unpaired = '0;
      for (int slot = 0; slot < TAG_DEPTH; slot++)
        if (SKEW_W'(slot) < positive_skew && aw_watch_q[slot]) watch_unpaired = watch_unpaired + CREDIT_W'(1);
    end

    assign watch_completed_credit = CREDIT_EXT_W'(response_occupancy);
    assign accepted_b = b_watch_hsk && response_occupancy != 0;
    assign response_source = watch_credit_inc && credit_has_room;
    assign response_select = (select_now && (skew < 0 || (skew == 0 && w_complete))) || (selected && w_dist == 1 && w_complete);
    assign outstanding = COUNT_W'(CREDIT_EXT_W'(response_occupancy) + CREDIT_EXT_W'(watch_unpaired));
    assign b_rank = !selected ? '0 : w_pending ? response_occupancy : response_rank;

    always_ff @(posedge clk or negedge rstn) begin
      if (!rstn) begin
        aw_watch_q <= '0;
      end else begin
        if (tag_pop) begin
          for (int slot = 0; slot < TAG_DEPTH-1; slot++) aw_watch_q[slot] <= aw_watch_q[slot+1];
          aw_watch_q[TAG_DEPTH-1] <= 1'b0;
        end
        if (tag_push && tag_append_index < TAG_DEPTH) aw_watch_q[tag_append_index] <= aw_id == watch_id;
      end
    end

    a_tracker_response_select_credit: assert property (response_select |-> response_source);
  end endgenerate
`else
  wire tracked_aw = aw_watch && (response_occupancy < MAX_OUTSTANDING || accepted_b);
  assign accepted_b = b_watch_hsk && response_occupancy != 0;
  assign response_source = tracked_aw;
  assign response_select = select_now;
  assign outstanding = response_occupancy;
  assign b_rank = response_rank;
`endif

  assign pending = selected && (w_pending || response_pending);
  assign completed = selected && !pending;

  fv_stream_occurrence_core #(.WIDTH(1), .MAX_PENDING(MAX_OUTSTANDING), .MAX_DELAY(MAX_RESPONSE_DELAY)) i_response (
    .clk(clk), .rstn(rstn), .select_now(response_select), .s_hsk(response_source), .s_data(1'b0), .m_hsk(accepted_b),
    .selected(), .pending(response_pending), .completed(),
    .watched_data(), .rank(response_rank), .occupancy(response_occupancy), .age()
  );

  s_select_request: assume property (select_now |-> aw_watch && (outstanding < MAX_OUTSTANDING || accepted_b) && !selected);
  s_select_once: assume property (selected |-> !select_now);

  x_no_orphan_response: `TXN_DEST property (b_watch |-> outstanding != 0);
  x_b_has_completed_write: `TXN_DEST property (pending && b_rank == 0 && b_watch |-> wr_data_complete);

`ifdef AXI_FVIP_MANAGER
  x_b_has_per_id_completed_write: assert property (b_watch |-> watch_completed_credit != 0);
  a_tracker_pending_w_rank: assert property (w_pending |-> skew > $signed({1'b0, w_rank}));
  a_tracker_pending_data_state: assert property (pending |-> w_pending || wr_data_complete);
  a_tracker_pending_w_credit_rank_exact: assert property (w_pending |-> watch_completed_credit == CREDIT_EXT_W'(b_rank));

  generate if (ENABLE_RESPONSE_PROGRESS) begin : g_response_progress
    x_write_response_progress: assert property (rsp_eligible |-> rsp_visible || rsp_age < MAX_RESPONSE_DELAY);
  end endgenerate
`endif

  c_select: cover property (select_now);
  c_select_with_rank: cover property (select_now && outstanding != 0);
  c_complete: cover property (completed);
  c_b_response: cover property (b_hsk);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      selected <= 1'b0;
      w_dist <= '0;
`ifdef AXI_FVIP_MANAGER
      rsp_age <= '0;
`endif
    end else begin
      if (select_now) begin
        selected <= 1'b1;
        w_dist <= skew < 0 || (skew == 0 && w_complete) ? '0 : SKEW_W'($unsigned(skew)) + SKEW_W'(1) - SKEW_W'(w_complete);
`ifdef AXI_FVIP_MANAGER
        rsp_age <= '0;
`endif
      end else if (w_dist != 0 && w_complete) begin
        w_dist <= w_dist - SKEW_W'(1);
`ifdef AXI_FVIP_MANAGER
        if (w_dist == 1) rsp_age <= '0;
`endif
      end

`ifdef AXI_FVIP_MANAGER
      if (ENABLE_RESPONSE_PROGRESS) begin
        if (!rsp_eligible || rsp_visible) rsp_age <= '0;
        else if (!b_stalled && rsp_age < MAX_RESPONSE_DELAY) rsp_age <= rsp_age + 1'b1;
      end
`endif
    end
  end
endmodule
