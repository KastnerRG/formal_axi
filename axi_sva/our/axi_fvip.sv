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
  parameter bit ENABLE_REQUEST_MAX_STALL = ENABLE_MAX_STALL,
  parameter bit ENABLE_RESPONSE_MAX_STALL = ENABLE_MAX_STALL,
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
  localparam int W_BEAT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1);
  localparam int W_PAYLOAD_W = DATA_W + DATA_W/8 + 1 + USER_W;
  localparam int W_PAYLOAD_BIT_W =
    (W_PAYLOAD_W < 2) ? 1 : $clog2(W_PAYLOAD_W);
`ifdef MASTER
  localparam bit MANAGER_IS_ENV = 1'b1;
`else
  localparam bit MANAGER_IS_ENV = 1'b0;
`endif

  // PULP packed records are the common representation at the public boundary.
  // Build each record in one procedural assignment.  Questa Formal can alias
  // neighboring packed fields (for example ARVALID into the ARID MSB) when the
  // record is driven by the macro's many continuous field assignments.  Role
  // FVIPs consume these records as packed bits after the first modport hop.
  always_comb begin
    `AXI_SET_TO_REQ(view.req, axi)
    `AXI_SET_TO_RESP(view.rsp, axi)
  end

  // Exact public live-channel view for role FVIPs.  Each payload is one
  // vector and each handshake signal is a distinct scalar, so no packed
  // req/rsp field can be mistaken for its neighbor by the formal frontend.
  assign view.live_aw = {
    axi.aw_id, axi.aw_addr, axi.aw_len, axi.aw_size, axi.aw_burst,
    axi.aw_lock, axi.aw_cache, axi.aw_prot, axi.aw_qos, axi.aw_region,
    axi.aw_atop, axi.aw_user
  };
  assign view.live_w = {
    axi.w_data, axi.w_strb, axi.w_last, axi.w_user
  };
  assign view.live_b = {axi.b_id, axi.b_resp, axi.b_user};
  assign view.live_ar = {
    axi.ar_id, axi.ar_addr, axi.ar_len, axi.ar_size, axi.ar_burst,
    axi.ar_lock, axi.ar_cache, axi.ar_prot, axi.ar_qos, axi.ar_region,
    axi.ar_user
  };
  assign view.live_r = {
    axi.r_id, axi.r_data, axi.r_resp, axi.r_last, axi.r_user
  };
  assign view.live_aw_valid = axi.aw_valid;
  assign view.live_aw_ready = axi.aw_ready;
  assign view.live_w_valid = axi.w_valid;
  assign view.live_w_ready = axi.w_ready;
  assign view.live_b_valid = axi.b_valid;
  assign view.live_b_ready = axi.b_ready;
  assign view.live_ar_valid = axi.ar_valid;
  assign view.live_ar_ready = axi.ar_ready;
  assign view.live_r_valid = axi.r_valid;
  assign view.live_r_ready = axi.r_ready;

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

  logic [W_BEAT_W-1:0] channel_w_beat;
  assign view.channel_w_beat = channel_w_beat;
  axi_channel_fvip #(
    .DATA_W(DATA_W),
    .MAX_STALL(MAX_STALL), .ENABLE_MAX_STALL(ENABLE_MAX_STALL),
    .ENABLE_REQUEST_MAX_STALL(ENABLE_REQUEST_MAX_STALL),
    .ENABLE_RESPONSE_MAX_STALL(ENABLE_RESPONSE_MAX_STALL),
    .ENABLE_EXCLUSIVE(ENABLE_EXCLUSIVE), .ENABLE_ATOP(ENABLE_ATOP),
    .MAX_BURST_LEN(MAX_BURST_LEN), .MANAGER_IS_ENV(MANAGER_IS_ENV)
  ) u_channel (
    .clk(clk), .rstn(rstn), .axi(axi), .w_beat(channel_w_beat)
  );

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
    ) i_contract (
      .clk(clk), .rstn(rstn), .current_w_beat(channel_w_beat), .axi(axi)
    );
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
    ) u_txn (
      .clk(clk), .rstn(rstn), .w_beat(channel_w_beat), .axi(axi)
    );

    // Read and write data sampling are each universally quantified over the
    // burst beat. Reuse the pair tracker's arbitrary beat choice.
    wire [WATCH_BEAT_W-1:0] rd_watch_beat =
      u_txn.i_aw_w_tracker.watch_beat;
    logic [DATA_W-1:0] wr_watch_data;
    logic [DATA_W/8-1:0] wr_watch_strb;
    logic wr_watch_last;
    logic [USER_W-1:0] wr_watch_user;
    (* anyconst *) logic [W_PAYLOAD_BIT_W-1:0] pair_w_payload_idx;
    logic rolling_w_payload_bit;
    logic selected_w_payload_bit;
    logic selected_w_payload_valid;

    wire live_w_payload_bit = pair_w_payload_idx < W_PAYLOAD_W ?
      view.live_w[pair_w_payload_idx] : 1'b0;
    wire [W_PAYLOAD_W-1:0] rolling_w_payload = {
      wr_watch_data, wr_watch_strb, wr_watch_last, wr_watch_user
    };
    wire pair_w_live_owner =
      (u_txn.i_aw_w_tracker.pending_aw &&
       u_txn.i_aw_w_tracker.rank == 0) ||
      (u_txn.i_aw_w_tracker.select_aw &&
       u_txn.i_aw_w_tracker.skew == 0);
    wire pair_w_complete_now =
      u_txn.i_aw_w_tracker.select_w ||
      (u_txn.i_aw_w_tracker.select_aw && w_hsk && axi.w_last &&
       u_txn.i_aw_w_tracker.skew == 0) ||
      (u_txn.i_aw_w_tracker.pending_aw && w_hsk && axi.w_last &&
       u_txn.i_aw_w_tracker.rank == 0);

    s_pair_w_payload_idx_constant: assume property (
      @(posedge clk) disable iff ($isunknown(rstn))
        $stable(pair_w_payload_idx));
    c_pair_w_payload_idx_range: assume property (
      @(posedge clk) disable iff ($isunknown(rstn))
        pair_w_payload_idx < W_PAYLOAD_W);

    always_comb begin
      view.global_wr_outstanding = u_txn.wr_outstanding;
      view.rd_select = u_txn.i_rd_tracker.select_now;
      view.rd_watch_id = u_txn.i_rd_tracker.watch_id;
      view.rd_selected = u_txn.i_rd_tracker.selected;
      view.rd_pending = u_txn.i_rd_tracker.pending;
      view.rd_completed = u_txn.i_rd_tracker.completed;
      view.rd_rank = u_txn.i_rd_tracker.rank;
      view.rd_outstanding = u_txn.i_rd_tracker.outstanding;
      view.rd_beat_idx = rd_watch_beat;
      view.rd_rsp_beat = u_txn.i_rd_tracker.watched_beat;
      view.rd_rsp_visible = u_txn.i_rd_tracker.rsp_visible;
      view.rd_rsp_complete =
        u_txn.i_rd_tracker.rsp_visible && r_hsk && axi.r_last;
`ifdef MASTER
      view.rd_rsp_wait_cycles = u_txn.i_rd_tracker.rsp_age;
`else
      view.rd_rsp_wait_cycles = '0;
`endif

      view.wr_select = u_txn.i_wr_b_tracker.select_now;
      view.wr_watch_id = u_txn.i_wr_b_tracker.watch_id;
      view.wr_selected = u_txn.i_wr_b_tracker.selected;
      view.wr_pending = u_txn.i_wr_b_tracker.pending;
      view.wr_completed = u_txn.i_wr_b_tracker.completed;
      view.wr_rank = u_txn.i_wr_b_tracker.b_rank;
      view.wr_outstanding = u_txn.i_wr_b_tracker.outstanding;
      view.wr_data_pending = u_txn.i_wr_b_tracker.w_pending;
      view.wr_data_rank = u_txn.i_wr_b_tracker.w_rank;
      view.wr_data_complete = u_txn.i_wr_b_tracker.wr_data_complete;
      view.wr_rsp_visible = u_txn.i_wr_b_tracker.rsp_visible;
      view.wr_rsp_complete =
        u_txn.i_wr_b_tracker.rsp_visible && b_hsk;
`ifdef MASTER
      view.wr_rsp_wait_cycles = u_txn.i_wr_b_tracker.rsp_age;
`else
      view.wr_rsp_wait_cycles = '0;
`endif

      view.pair_select_aw = u_txn.i_aw_w_tracker.select_aw;
      view.pair_select_w = u_txn.i_aw_w_tracker.select_w;
      view.pair_selected = u_txn.i_aw_w_tracker.selected;
      view.pair_pending_aw = u_txn.i_aw_w_tracker.pending_aw;
      view.pair_pending_w = u_txn.i_aw_w_tracker.pending_w;
      view.pair_completed = u_txn.i_aw_w_tracker.completed;
      view.pair_rank = u_txn.i_aw_w_tracker.rank;
      view.pair_skew = u_txn.write_skew;
      view.wr_beat_idx = u_txn.i_aw_w_tracker.watch_beat;
      view.pair_w_payload_idx = pair_w_payload_idx;
      view.pair_w_payload_bit = selected_w_payload_bit;
      view.pair_w_payload_available = selected_w_payload_valid;
      view.wr_data_visible = pair_w_live_owner && axi.w_valid;
      view.wr_data_burst_complete =
        pair_w_live_owner && w_hsk && axi.w_last;
`ifdef MASTER
      view.wr_data_wait_cycles = '0;
`else
      view.wr_data_wait_cycles = u_txn.i_aw_w_tracker.wr_data_age;
`endif
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
        rolling_w_payload_bit <= 1'b0;
        selected_w_payload_bit <= 1'b0;
        selected_w_payload_valid <= 1'b0;
      end else begin
        if (u_txn.i_rd_tracker.select_now) begin
          view.rd_ar <= view.req.ar;
          view.rd_beat_sampled <= 1'b0;
        end
        if (u_txn.i_rd_tracker.rsp_visible && r_hsk &&
            u_txn.i_rd_tracker.watched_beat == rd_watch_beat) begin
          view.rd_r <= view.rsp.r;
          view.rd_beat_sampled <= 1'b1;
        end

        if (u_txn.i_wr_b_tracker.select_now)
          view.wr_aw <= view.req.aw;
        if (u_txn.i_wr_b_tracker.rsp_visible && b_hsk)
          view.wr_b <= view.rsp.b;

        if (w_hsk && u_txn.i_aw_w_tracker.current_w_beat == u_txn.i_aw_w_tracker.watch_beat) begin
          wr_watch_data <= axi.w_data;
          wr_watch_strb <= axi.w_strb;
          wr_watch_last <= axi.w_last;
          wr_watch_user <= axi.w_user;
        end
        if (!(u_txn.i_aw_w_tracker.pending_w ||
              u_txn.i_aw_w_tracker.completed) &&
            w_hsk &&
            u_txn.i_aw_w_tracker.current_w_beat ==
              u_txn.i_aw_w_tracker.watch_beat)
          rolling_w_payload_bit <= live_w_payload_bit;

        if (u_txn.i_aw_w_tracker.select_aw ||
            (u_txn.i_aw_w_tracker.select_w && aw_hsk &&
             u_txn.i_aw_w_tracker.skew == 0) ||
            (u_txn.i_aw_w_tracker.pending_w && aw_hsk &&
             u_txn.i_aw_w_tracker.rank == 0))
          view.pair_aw <= view.req.aw;
        if (u_txn.i_aw_w_tracker.select_aw) begin
          view.wr_beat_sampled <= 1'b0;
          selected_w_payload_valid <= 1'b0;
        end

        // If an AW is selected at count parity after the arbitrary beat of an
        // in-progress W packet has already handshaken, publish the existing
        // rolling sample immediately.  Positive skew deliberately cannot use
        // this prefix because it belongs to an older W packet.
        if (u_txn.i_aw_w_tracker.select_aw &&
            u_txn.i_aw_w_tracker.skew == 0 &&
            u_txn.i_aw_w_tracker.watch_beat <
              u_txn.i_aw_w_tracker.current_w_beat) begin
          view.wr_w.data <= wr_watch_data;
          view.wr_w.strb <= wr_watch_strb;
          view.wr_w.last <= wr_watch_last;
          view.wr_w.user <= wr_watch_user;
          view.wr_beat_sampled <= 1'b1;
          selected_w_payload_bit <= rolling_w_payload_bit;
          selected_w_payload_valid <= 1'b1;
        end

        // Publish the selected watched beat on its handshake rather than
        // waiting for WLAST.  Stalled beats remain live observations and are
        // intentionally not called stored snapshots yet.
        if (pair_w_live_owner && w_hsk &&
            u_txn.i_aw_w_tracker.current_w_beat ==
              u_txn.i_aw_w_tracker.watch_beat) begin
          view.wr_w <= view.req.w;
          view.wr_beat_sampled <= 1'b1;
          selected_w_payload_bit <= live_w_payload_bit;
          selected_w_payload_valid <= 1'b1;
        end

        if (pair_w_complete_now) begin
          view.wr_beat_sampled <= u_txn.i_aw_w_tracker.watch_beat < u_txn.i_aw_w_tracker.current_w_beats;
          selected_w_payload_valid <=
            u_txn.i_aw_w_tracker.watch_beat <
              u_txn.i_aw_w_tracker.current_w_beats;
          if (u_txn.i_aw_w_tracker.current_w_beat == u_txn.i_aw_w_tracker.watch_beat) begin
            view.wr_w <= view.req.w;
            selected_w_payload_bit <= live_w_payload_bit;
          end else begin
            view.wr_w.data <= wr_watch_data;
            view.wr_w.strb <= wr_watch_strb;
            view.wr_w.last <= wr_watch_last;
            view.wr_w.user <= wr_watch_user;
            selected_w_payload_bit <= rolling_w_payload_bit;
          end
        end
      end
    end

    // Public selected-write response refinement.  The role checker may reuse
    // this endpoint-owned selector instead of duplicating a same-ID B rank.
    // Capture is keyed to the exact selected response handshake; completion
    // is the validity bit for the stored snapshot, and the snapshot freezes
    // after that occurrence.  These assertions add no observer state.
    a_view_wr_select_state: assert property (
      view.wr_select |=>
        view.wr_selected && view.wr_pending);
    a_view_wr_rsp_complete_exact: assert property (
      view.wr_rsp_complete ==
        (view.wr_rsp_visible && view.live_b_ready));
    a_view_wr_b_capture: assert property (
      view.wr_rsp_complete |=>
        {view.wr_b.id, view.wr_b.resp, view.wr_b.user} ==
          $past(view.live_b));
    a_view_wr_b_provenance: assert property (
      $past(rstn) && $rose(view.wr_completed) |->
        $past(view.wr_rsp_complete));
    a_view_wr_b_frozen: assert property (
      view.wr_completed |=> $stable(view.wr_b));

    c_view_wr_select: cover property (view.wr_select);
    c_view_wr_b_stalled_live: cover property (
      view.wr_rsp_visible && !view.live_b_ready);
    c_view_wr_b_capture: cover property (view.wr_rsp_complete);
    c_view_wr_b_stored: cover property (view.wr_completed);

    // The public pair-AW snapshot must mirror every address capture in the
    // generic pair tracker.  Compare against the flat live-channel boundary
    // so these lemmas also audit the packed req/view representation.
    a_view_pair_aw_capture_select_aw: assert property (
      u_txn.i_aw_w_tracker.select_aw |=>
        view.pair_aw == $past(view.live_aw));
    a_view_pair_aw_capture_select_w_join: assert property (
      u_txn.i_aw_w_tracker.select_w && aw_hsk &&
        u_txn.i_aw_w_tracker.skew == 0 |=>
          view.pair_aw == $past(view.live_aw));
    a_view_pair_aw_capture_pending_w_join: assert property (
      u_txn.i_aw_w_tracker.pending_w && aw_hsk &&
        u_txn.i_aw_w_tracker.rank == 0 |=>
          view.pair_aw == $past(view.live_aw));
    a_view_pair_aw_frozen: assert property (
      (u_txn.i_aw_w_tracker.pending_aw ||
        u_txn.i_aw_w_tracker.completed) |=>
          $stable(view.pair_aw));

    // The scalar role-payload observer is staged beside the full public W
    // snapshot.  These equivalences are the deletion gate for the two wide
    // payload registers; they do not participate in protocol WSTRB checking.
    a_view_pair_w_rolling_scalar_capture: assert property (
      !(u_txn.i_aw_w_tracker.pending_w ||
        u_txn.i_aw_w_tracker.completed) &&
        w_hsk &&
        u_txn.i_aw_w_tracker.current_w_beat ==
          u_txn.i_aw_w_tracker.watch_beat |=>
            rolling_w_payload_bit == $past(live_w_payload_bit));
    a_view_pair_w_rolling_scalar_full_equiv: assert property (
      !(u_txn.i_aw_w_tracker.pending_w ||
        u_txn.i_aw_w_tracker.completed) |->
          rolling_w_payload_bit ==
            rolling_w_payload[pair_w_payload_idx]);
    a_view_pair_w_scalar_full_equiv: assert property (
      selected_w_payload_valid == view.wr_beat_sampled &&
      (!selected_w_payload_valid ||
       selected_w_payload_bit == view.wr_w[pair_w_payload_idx]));
    a_view_pair_w_prefix_seed: assert property (
      u_txn.i_aw_w_tracker.select_aw &&
        u_txn.i_aw_w_tracker.skew == 0 &&
        u_txn.i_aw_w_tracker.watch_beat <
          u_txn.i_aw_w_tracker.current_w_beat |=>
            selected_w_payload_valid &&
            selected_w_payload_bit == $past(rolling_w_payload_bit));
    a_view_pair_w_live_capture: assert property (
      pair_w_live_owner && w_hsk &&
        u_txn.i_aw_w_tracker.current_w_beat ==
          u_txn.i_aw_w_tracker.watch_beat |=>
            selected_w_payload_valid &&
            selected_w_payload_bit == $past(live_w_payload_bit));
    a_view_pair_w_completion_capture: assert property (
      pair_w_complete_now |=>
        selected_w_payload_valid ==
          $past(u_txn.i_aw_w_tracker.watch_beat <
                u_txn.i_aw_w_tracker.current_w_beats) &&
        (!$past(u_txn.i_aw_w_tracker.watch_beat <
                u_txn.i_aw_w_tracker.current_w_beats) ||
         selected_w_payload_bit ==
           $past(u_txn.i_aw_w_tracker.current_w_beat ==
                   u_txn.i_aw_w_tracker.watch_beat ?
                 live_w_payload_bit : rolling_w_payload_bit)));
    a_view_pair_w_scalar_frozen: assert property (
      selected_w_payload_valid |=>
        selected_w_payload_valid &&
        $stable(selected_w_payload_bit) &&
        view.wr_beat_sampled && $stable(view.wr_w));
    a_view_pair_w_scalar_export_exact: assert property (
      view.pair_w_payload_idx == pair_w_payload_idx &&
      view.pair_w_payload_bit == selected_w_payload_bit &&
      view.pair_w_payload_available == selected_w_payload_valid);
    a_view_pair_w_completed_availability: assert property (
      u_txn.i_aw_w_tracker.completed |->
        view.pair_w_payload_available ==
          (u_txn.i_aw_w_tracker.watch_beat <
           u_txn.i_aw_w_tracker.watched_w_beats));
    a_view_pair_w_visible_exact: assert property (
      view.wr_data_visible ==
        (pair_w_live_owner && view.live_w_valid));
    a_view_pair_w_complete_exact: assert property (
      view.wr_data_burst_complete ==
        (pair_w_live_owner && view.live_w_valid && view.live_w_ready &&
         view.live_w[USER_W]));

    c_view_pair_aw_capture_select_aw: cover property (
      u_txn.i_aw_w_tracker.select_aw);
    c_view_pair_aw_capture_select_w_join: cover property (
      u_txn.i_aw_w_tracker.select_w && aw_hsk &&
        u_txn.i_aw_w_tracker.skew == 0);
    c_view_pair_aw_capture_pending_w_join: cover property (
      u_txn.i_aw_w_tracker.pending_w && aw_hsk &&
        u_txn.i_aw_w_tracker.rank == 0);
    c_view_pair_w_prefix_seed: cover property (
      u_txn.i_aw_w_tracker.select_aw &&
        u_txn.i_aw_w_tracker.skew == 0 &&
        u_txn.i_aw_w_tracker.watch_beat <
          u_txn.i_aw_w_tracker.current_w_beat);
    c_view_pair_w_pending_aw_early_capture: cover property (
      u_txn.i_aw_w_tracker.pending_aw &&
        u_txn.i_aw_w_tracker.rank == 0 && w_hsk && !axi.w_last &&
        u_txn.i_aw_w_tracker.current_w_beat ==
          u_txn.i_aw_w_tracker.watch_beat);
    c_view_pair_w_select_aw_live_capture: cover property (
      u_txn.i_aw_w_tracker.select_aw &&
        u_txn.i_aw_w_tracker.skew == 0 && w_hsk &&
        u_txn.i_aw_w_tracker.current_w_beat ==
          u_txn.i_aw_w_tracker.watch_beat);
    c_view_pair_w_select_w_prior_capture: cover property (
      u_txn.i_aw_w_tracker.select_w &&
        u_txn.i_aw_w_tracker.watch_beat <
          u_txn.i_aw_w_tracker.current_w_beat);
    c_view_pair_w_select_w_final_capture: cover property (
      u_txn.i_aw_w_tracker.select_w &&
        u_txn.i_aw_w_tracker.watch_beat ==
          u_txn.i_aw_w_tracker.current_w_beat);
    c_view_pair_w_select_aw_stalled_offer: cover property (
      u_txn.i_aw_w_tracker.select_aw &&
        u_txn.i_aw_w_tracker.skew == 0 && axi.w_valid && !axi.w_ready &&
        u_txn.i_aw_w_tracker.current_w_beat ==
          u_txn.i_aw_w_tracker.watch_beat);
    c_view_pair_w_pending_aw_stalled_offer: cover property (
      u_txn.i_aw_w_tracker.pending_aw &&
        u_txn.i_aw_w_tracker.rank == 0 && axi.w_valid && !axi.w_ready &&
        u_txn.i_aw_w_tracker.current_w_beat ==
          u_txn.i_aw_w_tracker.watch_beat);
    c_view_pair_w_complete_select_w: cover property (
      u_txn.i_aw_w_tracker.select_w);
    c_view_pair_w_complete_select_aw: cover property (
      u_txn.i_aw_w_tracker.select_aw &&
        u_txn.i_aw_w_tracker.skew == 0 && w_hsk && axi.w_last);
    c_view_pair_w_complete_pending_aw: cover property (
      u_txn.i_aw_w_tracker.pending_aw &&
        u_txn.i_aw_w_tracker.rank == 0 && w_hsk && axi.w_last);
  end else begin : g_no_txn
    always_comb begin
      view.global_wr_outstanding = '0;
      view.rd_select = 1'b0;
      view.rd_watch_id = '0;
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
      view.wr_watch_id = '0;
      view.wr_selected = 1'b0;
      view.wr_pending = 1'b0;
      view.wr_completed = 1'b0;
      view.wr_rank = '0;
      view.wr_outstanding = '0;
      view.wr_aw = '0;
      view.wr_data_pending = 1'b0;
      view.wr_data_rank = '0;
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
      view.pair_skew = '0;
      view.pair_aw = '0;
      view.wr_beat_idx = '0;
      view.wr_w = '0;
      view.wr_beat_sampled = 1'b0;
      view.pair_w_payload_idx = '0;
      view.pair_w_payload_bit = 1'b0;
      view.pair_w_payload_available = 1'b0;
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
