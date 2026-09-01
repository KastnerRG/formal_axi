`include "axi_switch_fvip.svh"
`include "axi/assign.svh"

// Standalone bounded AXI4 endpoint checker.
//
// Polarity is selected by axi_switch_fvip.svh:
//   m_axi_fvip checks an environment Manager against a DUT Subordinate.
//   s_axi_fvip checks a DUT Manager against an environment Subordinate.
// Every rule follows ownership: environment-driven behavior is assumed and
// DUT-driven behavior is asserted.  Role behavior is intentionally absent.
module `MODNAME_AXI #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int MAX_STALL = 8,
  parameter bit ENABLE_MAX_STALL = 1'b0,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter bit ENABLE_EXCLUSIVE = 1'b0,
  parameter bit ENABLE_ATOP = 1'b0,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_TRANSACTION = 1'b1,
  parameter bit ENABLE_ENV_TRANSACTION_CONTRACT = 1'b1,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16
) (
  input logic clk,
  input logic rstn,
  AXI_BUS.Monitor axi,
  axi_fvip_txn_view_if.Producer view
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int WATCH_BEAT_W =
    (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN);
`ifdef MASTER
  localparam bit MANAGER_IS_ENV = 1'b1;
`else
  localparam bit MANAGER_IS_ENV = 1'b0;
`endif

  // PULP packed records are the common representation at the public boundary.
  always_comb begin
    `AXI_SET_TO_REQ(view.req, axi)
    `AXI_SET_TO_RESP(view.rsp, axi)
  end

  wire aw_hsk = axi.aw_valid && axi.aw_ready;
  wire w_hsk = axi.w_valid && axi.w_ready;
  wire b_hsk = axi.b_valid && axi.b_ready;
  wire ar_hsk = axi.ar_valid && axi.ar_ready;
  wire r_hsk = axi.r_valid && axi.r_ready;

  // Reset is an external formal-harness contract, independent of AXI role.
  logic rstn_at_posedge;
  logic rstn_released = 1'b0;
  always_ff @(posedge clk) rstn_at_posedge <= rstn;
  always_ff @(posedge clk) rstn_released <= rstn_released || rstn;

  a_rstn_rises_with_posedge:
    assume property (@(negedge clk) disable iff ($isunknown(rstn))
      rstn |-> rstn_at_posedge);
  a_rstn_falls_with_posedge:
    assume property (@(negedge clk) disable iff ($isunknown(rstn))
      !rstn |-> !rstn_at_posedge);
  always_comb begin : a_rstn_no_reassert
    assume (!rstn_released || rstn);
  end

  axi_channel_fvip #(
    .DATA_W(DATA_W),
    .MAX_STALL(MAX_STALL), .ENABLE_MAX_STALL(ENABLE_MAX_STALL),
    .ENABLE_EXCLUSIVE(ENABLE_EXCLUSIVE), .ENABLE_ATOP(ENABLE_ATOP),
    .MAX_BURST_LEN(MAX_BURST_LEN), .MANAGER_IS_ENV(MANAGER_IS_ENV)
  ) u_channel (.clk(clk), .rstn(rstn), .axi(axi));

  // Selector-based assumptions are insufficient because the environment can
  // avoid selecting a bad occurrence.  Constrain every environment-owned
  // txn with the matching deterministic bounded contract.
  generate if (ENABLE_TRANSACTION && ENABLE_ENV_TRANSACTION_CONTRACT) begin : g_env
`ifdef MASTER
    axi_fvip_manager_env_contract #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W),
      .MAX_OUTSTANDING(MAX_OUTSTANDING),
      .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
      .MAX_BURST_LEN(MAX_BURST_LEN),
      .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS),
      .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
    ) i_contract (.clk(clk), .rstn(rstn), .axi(axi));
`else
    axi_fvip_subordinate_env_contract #(
      .ID_W(ID_W), .MAX_OUTSTANDING(MAX_OUTSTANDING),
      .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
      .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
      .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY)
    ) i_contract (.clk(clk), .rstn(rstn), .axi(axi));
`endif
  end endgenerate

  generate if (ENABLE_TRANSACTION) begin : g_txn
    `MODNAME_TXN #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
      .MAX_READ_OUTSTANDING(MAX_OUTSTANDING),
      .MAX_WRITE_OUTSTANDING(MAX_OUTSTANDING),
      .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
      .MAX_BURST_LEN(MAX_BURST_LEN),
      .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
      .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY),
      .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS),
      .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
    ) u_txn (.clk(clk), .rstn(rstn), .axi(axi));

    (* anyconst *) logic [WATCH_BEAT_W-1:0] rd_watch_beat;
    logic [DATA_W-1:0] wr_watch_data;
    logic [DATA_W/8-1:0] wr_watch_strb;
    logic wr_watch_last;
    logic [USER_W-1:0] wr_watch_user;

    s_rd_watch_beat_constant:
      assume property (@(posedge clk) disable iff ($isunknown(rstn))
        $stable(rd_watch_beat));
    s_rd_watch_beat_range:
      assume property (@(posedge clk) disable iff ($isunknown(rstn))
        rd_watch_beat < MAX_BURST_LEN);

    always_comb begin
      view.rd_select = u_txn.i_rd_tracker.select_now;
      view.rd_selected = u_txn.i_rd_tracker.selected;
      view.rd_pending = u_txn.i_rd_tracker.pending;
      view.rd_completed = u_txn.i_rd_tracker.completed;
      view.rd_rank = u_txn.i_rd_tracker.rank;
      view.rd_outstanding = u_txn.i_rd_tracker.outstanding;
      view.rd_beat_idx = rd_watch_beat;
      view.rd_rsp_beat = u_txn.i_rd_tracker.watched_beat;
      view.rd_rsp_visible = u_txn.i_rd_tracker.rsp_visible;
      view.rd_rsp_complete = u_txn.i_rd_tracker.pending &&
                             u_txn.i_rd_tracker.rank == 0 && r_hsk && axi.r_last;
      view.rd_rsp_wait_cycles = u_txn.i_rd_tracker.rsp_age;

      view.wr_select = u_txn.i_wr_b_tracker.select_now;
      view.wr_selected = u_txn.i_wr_b_tracker.selected;
      view.wr_pending = u_txn.i_wr_b_tracker.pending;
      view.wr_completed = u_txn.i_wr_b_tracker.completed;
      view.wr_rank = u_txn.i_wr_b_tracker.b_rank;
      view.wr_outstanding = u_txn.i_wr_b_tracker.outstanding;
      view.wr_data_complete = u_txn.i_wr_b_tracker.wr_data_complete;
      view.wr_rsp_visible = u_txn.i_wr_b_tracker.rsp_visible;
      view.wr_rsp_complete = u_txn.i_wr_b_tracker.pending &&
                             u_txn.i_wr_b_tracker.b_rank == 0 && b_hsk;
      view.wr_rsp_wait_cycles = u_txn.i_wr_b_tracker.rsp_age;

      view.pair_select_aw = u_txn.i_aw_w_tracker.select_aw;
      view.pair_select_w = u_txn.i_aw_w_tracker.select_w;
      view.pair_selected = u_txn.i_aw_w_tracker.selected;
      view.pair_pending_aw = u_txn.i_aw_w_tracker.pending_aw;
      view.pair_pending_w = u_txn.i_aw_w_tracker.pending_w;
      view.pair_completed = u_txn.i_aw_w_tracker.completed;
      view.pair_rank = u_txn.i_aw_w_tracker.rank;
      view.wr_beat_idx = u_txn.i_aw_w_tracker.watch_beat;
      view.wr_data_visible = u_txn.i_aw_w_tracker.wr_visible;
      view.wr_data_burst_complete = u_txn.i_aw_w_tracker.pending_aw &&
                                    u_txn.i_aw_w_tracker.rank == 0 && w_hsk && axi.w_last;
      view.wr_data_wait_cycles = u_txn.i_aw_w_tracker.wr_data_age;
    end

    always_ff @(posedge clk or negedge rstn) begin
      if (!rstn) begin
        view.rd_ar <= '0;
        view.rd_r <= '0;
        view.rd_beat_sampled <= 1'b0;
        view.wr_aw <= '0;
        view.wr_b <= '0;
        view.pair_aw <= '0;
        view.wr_w <= '0;
        view.wr_beat_sampled <= 1'b0;
        wr_watch_data <= '0;
        wr_watch_strb <= '0;
        wr_watch_last <= 1'b0;
        wr_watch_user <= '0;
      end else begin
        if (u_txn.i_rd_tracker.select_now) begin
          view.rd_ar <= view.req.ar;
          view.rd_beat_sampled <= 1'b0;
        end
        if (u_txn.i_rd_tracker.pending && u_txn.i_rd_tracker.rank == 0 && r_hsk &&
            u_txn.i_rd_tracker.watched_beat == rd_watch_beat) begin
          view.rd_r <= view.rsp.r;
          view.rd_beat_sampled <= 1'b1;
        end

        if (u_txn.i_wr_b_tracker.select_now)
          view.wr_aw <= view.req.aw;
        if (u_txn.i_wr_b_tracker.pending && u_txn.i_wr_b_tracker.b_rank == 0 && b_hsk)
          view.wr_b <= view.rsp.b;

        if (w_hsk && u_txn.i_aw_w_tracker.current_w_beat == u_txn.i_aw_w_tracker.watch_beat) begin
          wr_watch_data <= axi.w_data;
          wr_watch_strb <= axi.w_strb;
          wr_watch_last <= axi.w_last;
          wr_watch_user <= axi.w_user;
        end

        if (u_txn.i_aw_w_tracker.select_aw) begin
          view.pair_aw <= view.req.aw;
          view.wr_beat_sampled <= 1'b0;
        end else if (u_txn.i_aw_w_tracker.pending_w && aw_hsk && u_txn.i_aw_w_tracker.rank == 0) begin
          view.pair_aw <= view.req.aw;
        end

        if (u_txn.i_aw_w_tracker.select_w ||
            (u_txn.i_aw_w_tracker.select_aw && w_hsk && axi.w_last && u_txn.i_aw_w_tracker.skew == 0) ||
            (u_txn.i_aw_w_tracker.pending_aw && w_hsk && axi.w_last && u_txn.i_aw_w_tracker.rank == 0)) begin
          view.wr_beat_sampled <= u_txn.i_aw_w_tracker.watch_beat < u_txn.i_aw_w_tracker.current_w_beats;
          if (u_txn.i_aw_w_tracker.current_w_beat == u_txn.i_aw_w_tracker.watch_beat) begin
            view.wr_w <= view.req.w;
          end else begin
            view.wr_w.data <= wr_watch_data;
            view.wr_w.strb <= wr_watch_strb;
            view.wr_w.last <= wr_watch_last;
            view.wr_w.user <= wr_watch_user;
          end
        end
      end
    end
  end else begin : g_no_txn
    always_comb begin
      view.rd_select = 1'b0;
      view.rd_selected = 1'b0;
      view.rd_pending = 1'b0;
      view.rd_completed = 1'b0;
      view.rd_rank = '0;
      view.rd_outstanding = '0;
      view.rd_ar = '0;
      view.rd_beat_idx = '0;
      view.rd_rsp_beat = '0;
      view.rd_r = '0;
      view.rd_beat_sampled = 1'b0;
      view.rd_rsp_visible = 1'b0;
      view.rd_rsp_complete = 1'b0;
      view.rd_rsp_wait_cycles = '0;
      view.wr_select = 1'b0;
      view.wr_selected = 1'b0;
      view.wr_pending = 1'b0;
      view.wr_completed = 1'b0;
      view.wr_rank = '0;
      view.wr_outstanding = '0;
      view.wr_aw = '0;
      view.wr_data_complete = 1'b0;
      view.wr_b = '0;
      view.wr_rsp_visible = 1'b0;
      view.wr_rsp_complete = 1'b0;
      view.wr_rsp_wait_cycles = '0;
      view.pair_select_aw = 1'b0;
      view.pair_select_w = 1'b0;
      view.pair_selected = 1'b0;
      view.pair_pending_aw = 1'b0;
      view.pair_pending_w = 1'b0;
      view.pair_completed = 1'b0;
      view.pair_rank = '0;
      view.pair_aw = '0;
      view.wr_beat_idx = '0;
      view.wr_w = '0;
      view.wr_beat_sampled = 1'b0;
      view.wr_data_visible = 1'b0;
      view.wr_data_burst_complete = 1'b0;
      view.wr_data_wait_cycles = '0;
    end
  end endgenerate
endmodule

`undef MODNAME_AXI
`undef MODNAME_TXN
`undef MODNAME_READ_TRACKER
`undef MODNAME_PAIR_TRACKER
`undef MODNAME_WRITE_TRACKER
`undef TXN_SOURCE
`undef TXN_DEST
