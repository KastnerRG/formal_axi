`timescale 1ns/1ps
`include "axi/typedef.svh"

// Focused C3/C4 mutation model for the cross-channel checker.
//
//   0  legal normal transactions
//   1  R before AR
//   2  early RLAST
//   3  B before a completed write
//   4  W beat count disagrees with AWLEN
//   5  illegal WSTRB for the AW transfer geometry
//   6  wrong RID
//   7  wrong BID
//   8  same-ID reads returned with the second request's beat shape first
//   9  bounded read-response deadlock
//  10  duplicate B
//  11  legal selected-read rank compaction
//  12  legal selected-write rank compaction
//  13  AW accepted but required W data never becomes available
//  14  completed write never receives B
//  15  legal different-ID B reordering through the queued-join bypass
//  16  B for an ID whose AW is still waiting behind another ID's completed W
//  17  legal simultaneous unmatched-AW tag pop/push and ordered completion
//  18  legal W-before-AW completion credit
//  19  B cannot use a W-before-AW pair completed on the same sampled edge
//  20  legal stalled count-parity AW/W offer
//  21  illegal WSTRB on a stalled count-parity AW/W offer
//  22  missing WLAST on a stalled count-parity AW/W offer
//  23  late stalled AW exposes an illegal accepted partial-W prefix
//  24  late stalled AW exposes the wrong completed-W packet length
//  25  late stalled AW exposes an illegal completed-W strobe
//  26  legal mapped R offers remain live while both RREADYs are low
//  27  mapped R data corruption is visible before either R handshake
//  28  mapped R completion mismatch is visible before either R handshake
//  29  local-error RRESP corruption is visible while RREADY is low
//  30  local-error RDATA corruption is visible while RREADY is low
//  31  wrong-ID R offers do not consume the selected response occurrence
//  32  legal mapped B offers remain live while both BREADYs are low
//  33  mapped B corruption is visible before either B handshake
//  34  same-edge output WLAST cannot authorize a selected B offer
//  35  local-error BRESP corruption is visible while BREADY is low
//  36  wrong-ID B offers do not consume the selected response occurrence
//  37  a different-ID R handshake cannot update the selected public R view
//  38  a different-ID B handshake cannot update the selected public B view
//  39  an early same-ID B handshake cannot update the selected public B view
module tb_transaction_mutation #(
  parameter int MUTATION = 0
) (
  input logic clk,
  input logic rstn
);
  localparam int ADDR_W = 8;
  localparam int DATA_W = 16;
  localparam int ID_W = 2;
  localparam int MAX_BURST_LEN = 4;
  localparam int W_BEAT_W = $clog2(MAX_BURST_LEN + 1);

  logic [4:0] step;
  logic aw_valid, aw_ready;
  logic [ID_W-1:0] aw_id;
  logic [ADDR_W-1:0] aw_addr;
  logic [7:0] aw_len;
  logic [2:0] aw_size;
  logic [1:0] aw_burst;
  logic w_valid, w_ready;
  logic [DATA_W/8-1:0] w_strb;
  logic w_last;
  logic b_valid, b_ready;
  logic [ID_W-1:0] b_id;
  logic ar_valid, ar_ready;
  logic [ID_W-1:0] ar_id;
  logic [7:0] ar_len;
  logic r_valid, r_ready;
  logic [ID_W-1:0] r_id;
  logic r_last;
  logic rstn_at_posedge;
  logic rstn_released = 1'b0;
  logic [W_BEAT_W-1:0] channel_w_beat;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(ADDR_W), .AXI_DATA_WIDTH(DATA_W),
    .AXI_ID_WIDTH(ID_W), .AXI_USER_WIDTH(1)
  ) axi ();

  always_comb begin
    axi.aw_valid = aw_valid;
    axi.aw_ready = aw_ready;
    axi.aw_id = aw_id;
    axi.aw_addr = aw_addr;
    axi.aw_len = aw_len;
    axi.aw_size = aw_size;
    axi.aw_burst = aw_burst;
    axi.aw_lock = '0;
    axi.aw_cache = '0;
    axi.aw_prot = '0;
    axi.aw_qos = '0;
    axi.aw_region = '0;
    axi.aw_atop = '0;
    axi.aw_user = '0;
    axi.w_valid = w_valid;
    axi.w_ready = w_ready;
    axi.w_data = '0;
    axi.w_strb = w_strb;
    axi.w_last = w_last;
    axi.w_user = '0;
    axi.b_valid = b_valid;
    axi.b_ready = b_ready;
    axi.b_id = b_id;
    axi.b_resp = '0;
    axi.b_user = '0;
    axi.ar_valid = ar_valid;
    axi.ar_ready = ar_ready;
    axi.ar_id = ar_id;
    axi.ar_addr = '0;
    axi.ar_len = ar_len;
    axi.ar_size = '0;
    axi.ar_burst = '0;
    axi.ar_lock = '0;
    axi.ar_cache = '0;
    axi.ar_prot = '0;
    axi.ar_qos = '0;
    axi.ar_region = '0;
    axi.ar_user = '0;
    axi.r_valid = r_valid;
    axi.r_ready = r_ready;
    axi.r_id = r_id;
    axi.r_data = '0;
    axi.r_resp = '0;
    axi.r_last = r_last;
    axi.r_user = '0;
  end

  always_ff @(posedge clk) rstn_at_posedge <= rstn;
  always_ff @(posedge clk) rstn_released <= rstn_released || rstn;
  assume property (@(negedge clk) rstn == rstn_at_posedge);
  assume property (@(posedge clk) $past(rstn) |-> rstn);
  assume property (@(posedge clk) !rstn |=> rstn);
  always_comb assume (!rstn_released || rstn);

  always_ff @(posedge clk) begin
    if (!rstn) begin
      step <= '0;
      channel_w_beat <= '0;
    end else begin
      if (step != 5'h1f) step <= step + 1'b1;
      if (w_valid && w_ready && w_last)
        channel_w_beat <= '0;
      else if (w_valid && w_ready && channel_w_beat < MAX_BURST_LEN)
        channel_w_beat <= channel_w_beat + 1'b1;
    end
  end

  always_comb begin
    aw_valid = 1'b0;
    aw_ready = 1'b1;
    aw_id = 2'd0;
    aw_addr = 8'h00;
    aw_len = 8'd0;
    aw_size = 3'd0;
    aw_burst = 2'b01;
    w_valid = 1'b0;
    w_ready = 1'b1;
    w_strb = 2'b01;
    w_last = 1'b1;
    b_valid = 1'b0;
    b_ready = 1'b1;
    b_id = 2'd0;
    ar_valid = 1'b0;
    ar_ready = 1'b1;
    ar_id = 2'd0;
    ar_len = 8'd0;
    r_valid = 1'b0;
    r_ready = 1'b1;
    r_id = 2'd0;
    r_last = 1'b1;

    case (MUTATION)
      0: begin
        aw_valid = step == 1;
        w_valid = step == 2;
        // The completed AW/W pair is visible as join_write at step 3, so a
        // response here is legal without an extra oracle-queue cycle.
        b_valid = step == 3;
        ar_valid = step == 1;
        r_valid = step == 3;
      end
      1: begin
        r_valid = step == 1;
        ar_valid = step == 3;
      end
      2: begin
        ar_valid = step == 1;
        ar_len = 8'd1;
        r_valid = step == 3;
        r_last = 1'b1;
      end
      3: begin
        // A response may not anticipate AW and WLAST accepted on this same
        // edge.  This distinguishes raw acceptance from the queued bypass
        // exercised by the legal baseline above.
        b_valid = step == 1;
        aw_valid = step == 1;
        w_valid = step == 1;
      end
      4: begin
        aw_valid = step == 1;
        aw_len = 8'd1;
        w_valid = step == 2;
        w_last = 1'b1;
      end
      5: begin
        aw_valid = step == 1;
        w_valid = step == 2;
        // AWSIZE=0 and AWADDR[0]=0 permit lane 0 only.
        w_strb = 2'b10;
      end
      6: begin
        ar_valid = step == 1;
        r_valid = step == 3;
        r_id = 2'd1;
      end
      7: begin
        aw_valid = step == 1;
        w_valid = step == 2;
        b_valid = step == 4;
        b_id = 2'd1;
      end
      8: begin
        ar_valid = step == 1 || step == 2;
        ar_len = (step == 2) ? 8'd1 : 8'd0;
        r_valid = step == 4;
        r_last = 1'b0;
      end
      9: begin
        ar_valid = step == 1;
      end
      10: begin
        aw_valid = step == 1;
        w_valid = step == 2;
        b_valid = step == 4 || step == 5;
      end
      11: begin
        ar_valid = step == 1 || step == 2;
        // Retire the older request first, then the selected request.  This
        // exercises rank compaction without violating bounded response.
        r_valid = step == 3 || step == 5;
      end
      12: begin
        aw_valid = step == 1 || step == 2;
        w_valid = step == 1 || step == 2;
        // At step 3 the older queued response is popped while the second
        // prestate join is pushed into the same queue slot.
        b_valid = step == 3 || step == 5;
      end
      13: begin
        aw_valid = step == 1;
      end
      14: begin
        aw_valid = step == 1;
        w_valid = step == 2;
      end
      15: begin
        aw_valid = step == 1 || step == 2;
        aw_id = (step == 2) ? 2'd1 : 2'd0;
        w_valid = step == 1 || step == 2;
        // The ID-1 write joins at step 3 and may respond ahead of the older
        // queued ID-0 write.  The ID-0 response then retires normally.
        b_valid = step == 3 || step == 5;
        b_id = (step == 3) ? 2'd1 : 2'd0;
      end
      16: begin
        // W at step 3 completes the older ID-0 write only.  Global completed
        // credit therefore exists at step 4, but ID 1 has no completed write
        // and must not receive B yet.  This specifically exercises the
        // production arbitrary-ID unmatched-AW tag observer.
        aw_valid = step == 1 || step == 2;
        aw_id = (step == 2) ? 2'd1 : 2'd0;
        w_valid = step == 3;
        b_valid = step == 4;
        b_id = 2'd1;
      end
      17: begin
        // AW1 arrives exactly as W completes the older AW0: the tag observer
        // pops ID 0 and appends ID 1 into the vacated slot on the same edge.
        aw_valid = step == 1 || step == 2;
        aw_id = (step == 2) ? 2'd1 : 2'd0;
        w_valid = step == 2 || step == 4;
        b_valid = step == 3 || step == 5;
        b_id = (step == 5) ? 2'd1 : 2'd0;
      end
      18: begin
        // A previously completed W burst is paired by the later AW.  Its B
        // is legal only after that AW acceptance has updated the observers.
        w_valid = step == 1;
        aw_valid = step == 2;
        b_valid = step == 3;
      end
      19: begin
        // The same W-before-AW history, but B attempts to consume the pair on
        // the AW acceptance edge.  Credit is intentionally prestate-only.
        w_valid = step == 1;
        aw_valid = step == 2;
        b_valid = step == 2;
      end
      20: begin
        // A legal current packet and its live AW can both remain stalled.
        if (step >= 2) begin
          aw_valid = 1'b1;
          aw_ready = 1'b0;
          w_valid = 1'b1;
          w_ready = 1'b0;
        end
      end
      21: begin
        // At count parity the live AW already defines the current W geometry,
        // even though neither channel is permitted to handshake.
        if (step >= 2) begin
          aw_valid = 1'b1;
          aw_ready = 1'b0;
          w_valid = 1'b1;
          w_ready = 1'b0;
          w_strb = 2'b10;
        end
      end
      22: begin
        // AWLEN zero requires WLAST on this offered beat before either READY.
        if (step >= 2) begin
          aw_valid = 1'b1;
          aw_ready = 1'b0;
          w_valid = 1'b1;
          w_ready = 1'b0;
          w_last = 1'b0;
        end
      end
      23: begin
        // Capture an otherwise unconstrained partial W prefix, then expose
        // its illegal lane with a late AW that remains stalled.
        if (step == 1) begin
          w_valid = 1'b1;
          w_last = 1'b0;
          w_strb = 2'b10;
        end
        if (step >= 2) begin
          aw_valid = 1'b1;
          aw_ready = 1'b0;
          aw_len = 8'd1;
        end
      end
      24: begin
        // Select a completed one-beat W packet, then offer a late two-beat AW
        // without allowing the AW handshake.
        w_valid = step == 1;
        if (step >= 2) begin
          aw_valid = 1'b1;
          aw_ready = 1'b0;
          aw_len = 8'd1;
        end
      end
      25: begin
        // Select an illegal completed W strobe before its late AW metadata is
        // visible; the live AW offer must expose it without AWREADY.
        if (step == 1) begin
          w_valid = 1'b1;
          w_strb = 2'b10;
        end
        if (step >= 2) begin
          aw_valid = 1'b1;
          aw_ready = 1'b0;
        end
      end
      default: begin end
    endcase
  end

  // Exact bounded reference model.  This is deliberately instantiated only
  // in the verifier-validation harness, never in production FIFO closure.
  fv_axi_transaction_oracle #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
    .MAX_READ_OUTSTANDING(2), .MAX_WRITE_OUTSTANDING(2),
    .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) i_oracle (.*);

  // Response-side mutations are checked with Manager polarity; source-side
  // WLAST/WSTRB mutations use Subordinate polarity so those rules are asserts.
  generate if (MUTATION == 4 || MUTATION == 5 || MUTATION == 13 ||
               (MUTATION >= 20 && MUTATION <= 25)) begin : g_source
    subordinate_axi_transaction_fvip #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
      .MAX_READ_OUTSTANDING(2), .MAX_WRITE_OUTSTANDING(2),
      .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2),
      .MAX_BURST_LEN(MAX_BURST_LEN),
      .ENABLE_WRITE_DATA_PROGRESS(1'b1), .MAX_WRITE_DATA_DELAY(6)
    ) i_txn (
      .clk(clk), .rstn(rstn), .w_beat(channel_w_beat), .axi(axi)
    );
    if (MUTATION == 24 || MUTATION == 25) begin : g_select_w_before_aw
      a_select_completed_w: assume property (
        @(posedge clk) disable iff (!rstn)
        step == 1 |-> i_txn.i_aw_w_tracker.select_w);
    end
  end else begin : g_response
    manager_axi_transaction_fvip #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
      .MAX_READ_OUTSTANDING(2), .MAX_WRITE_OUTSTANDING(2),
      .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2),
      .MAX_BURST_LEN(MAX_BURST_LEN),
      .ENABLE_RESPONSE_PROGRESS(1'b1), .MAX_RESPONSE_DELAY(6)
    ) i_txn (
      .clk(clk), .rstn(rstn), .w_beat(channel_w_beat), .axi(axi)
    );
    if (MUTATION == 11) begin : g_read_rank_compaction
      a_select_second_read: assume property (
        @(posedge clk) disable iff (!rstn)
        step == 2 |-> i_txn.i_rd_tracker.select_now);
      a_read_rank_compacts: assert property (
        @(posedge clk) disable iff (!rstn)
        step == 4 |-> i_txn.i_rd_tracker.pending &&
          i_txn.i_rd_tracker.rank == 0 &&
          i_txn.i_rd_tracker.outstanding == 1);
    end
    if (MUTATION == 12) begin : g_write_rank_compaction
      a_select_second_write: assume property (
        @(posedge clk) disable iff (!rstn)
        step == 2 |-> i_txn.i_wr_b_tracker.select_now);
      a_write_rank_compacts: assert property (
        @(posedge clk) disable iff (!rstn)
        step == 4 |-> i_txn.i_wr_b_tracker.pending &&
          i_txn.i_wr_b_tracker.b_rank == 0 &&
          i_txn.i_wr_b_tracker.outstanding == 1);
    end
  end endgenerate

  // Cases 26--36 are role-checker unit mutations.  They deliberately use a
  // separate set of packed channels and public endpoint observations so the
  // original protocol/oracle cases above remain bit-for-bit unchanged.
  generate if (MUTATION >= 26 && MUTATION <= 36) begin : g_role_response
    tb_xbar_role_response_mutation #(.MUTATION(MUTATION)) i_role_case (
      .clk(clk), .rstn(rstn)
    );
  end endgenerate
  generate if (MUTATION >= 37 && MUTATION <= 39) begin : g_endpoint_view
    tb_axi_fvip_response_view_mutation #(.MUTATION(MUTATION)) i_view_case (
      .clk(clk), .rstn(rstn)
    );
  end endgenerate

  cover property (@(posedge clk) disable iff (!rstn) step == 6);
endmodule


// The READY-low role tests above consume the public visibility predicates,
// but cannot by themselves detect a bad handshake-capture implementation at
// that boundary.  These three focused endpoint cases prove that unrelated-ID
// and pre-data B/R handshakes leave the selected public response view alone.
module tb_axi_fvip_response_view_mutation #(
  parameter int MUTATION = 37
) (
  input logic clk,
  input logic rstn
);
  localparam int ADDR_W = 8;
  localparam int DATA_W = 16;
  localparam int ID_W = 2;
  localparam int USER_W = 1;
  localparam int MAX_BURST_LEN = 4;

  logic [3:0] step;
  AXI_BUS #(
    .AXI_ADDR_WIDTH(ADDR_W), .AXI_DATA_WIDTH(DATA_W),
    .AXI_ID_WIDTH(ID_W), .AXI_USER_WIDTH(USER_W)
  ) axi ();
  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(2), .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2),
    .MAX_BURST_LEN(MAX_BURST_LEN), .MAX_RESPONSE_DELAY(6),
    .MAX_WRITE_DATA_DELAY(6)
  ) view ();

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn)
      step <= '0;
    else if (step != 4'hf)
      step <= step + 1'b1;
  end

  always_comb begin
    axi.aw_valid = 1'b0;
    axi.aw_ready = 1'b1;
    axi.aw_id = '0;
    axi.aw_addr = '0;
    axi.aw_len = 8'd0;
    axi.aw_size = 3'd0;
    axi.aw_burst = 2'b01;
    axi.aw_lock = '0;
    axi.aw_cache = '0;
    axi.aw_prot = '0;
    axi.aw_qos = '0;
    axi.aw_region = '0;
    axi.aw_atop = '0;
    axi.aw_user = '0;
    axi.w_valid = 1'b0;
    axi.w_ready = 1'b1;
    axi.w_data = '0;
    axi.w_strb = 2'b01;
    axi.w_last = 1'b1;
    axi.w_user = '0;
    axi.b_valid = 1'b0;
    axi.b_ready = 1'b1;
    axi.b_id = '0;
    axi.b_resp = axi_pkg::RESP_OKAY;
    axi.b_user = '0;
    axi.ar_valid = 1'b0;
    axi.ar_ready = 1'b1;
    axi.ar_id = '0;
    axi.ar_addr = '0;
    axi.ar_len = 8'd0;
    axi.ar_size = 3'd0;
    axi.ar_burst = 2'b01;
    axi.ar_lock = '0;
    axi.ar_cache = '0;
    axi.ar_prot = '0;
    axi.ar_qos = '0;
    axi.ar_region = '0;
    axi.ar_user = '0;
    axi.r_valid = 1'b0;
    axi.r_ready = 1'b1;
    axi.r_id = '0;
    axi.r_data = '0;
    axi.r_resp = axi_pkg::RESP_OKAY;
    axi.r_last = 1'b1;
    axi.r_user = '0;

    case (MUTATION)
      37: begin
        axi.ar_valid = step == 1 || step == 2;
        axi.ar_id = step == 2 ? ID_W'(1) : ID_W'(0);
        axi.r_valid = step == 3 || step == 4;
        axi.r_id = step == 3 ? ID_W'(1) : ID_W'(0);
        if (step == 3)
          axi.r_data = DATA_W'(1);
      end
      38: begin
        axi.aw_valid = step == 1 || step == 2;
        axi.aw_id = step == 2 ? ID_W'(1) : ID_W'(0);
        axi.w_valid = step == 1 || step == 2;
        axi.b_valid = step == 3 || step == 4;
        axi.b_id = step == 3 ? ID_W'(1) : ID_W'(0);
        if (step == 3) begin
          axi.b_resp = axi_pkg::RESP_DECERR;
          axi.b_user = '1;
        end
      end
      39: begin
        axi.aw_valid = step == 1;
        axi.w_valid = step == 3;
        axi.b_valid = step == 2 || step == 4;
        if (step == 2) begin
          axi.b_resp = axi_pkg::RESP_DECERR;
          axi.b_user = '1;
        end
      end
      default: begin end
    endcase
  end

  manager_axi_fvip #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_STALL(6), .ENABLE_MAX_STALL(1'b0),
    .MAX_OUTSTANDING(2), .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2),
    .MAX_BURST_LEN(MAX_BURST_LEN), .ENABLE_TRANSACTION(1'b1),
    .ENABLE_ENV_TRANSACTION_CONTRACT(1'b0),
    .ENABLE_RESPONSE_PROGRESS(1'b0),
    .MAX_RESPONSE_DELAY(6), .ENABLE_WRITE_DATA_PROGRESS(1'b0),
    .MAX_WRITE_DATA_DELAY(6)
  ) i_endpoint (
    .clk(clk), .rstn(rstn), .axi(axi), .view(view)
  );

  // The public read and write views share this endpoint-wide arbitrary ID
  // partition.  Pin it explicitly in the deterministic validation harness;
  // forcing a selector pulse alone is not a constant-domain constraint.
  a_watch_id_zero: assume property (
    @(posedge clk) i_endpoint.g_txn.u_txn.watch_id == ID_W'(0));

  if (MUTATION == 37) begin : g_read_view_guard
    a_select_first_read: assume property (
      @(posedge clk) disable iff (!rstn)
      step == 1 |-> i_endpoint.g_txn.u_txn.i_rd_tracker.select_now);
    a_watch_first_read_beat: assume property (
      @(posedge clk) i_endpoint.g_txn.u_txn.i_aw_w_tracker.watch_beat == 0);
    a_wrong_r_does_not_complete_view: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !view.rd_rsp_complete);
    a_wrong_r_does_not_capture_view: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 4 |-> !view.rd_beat_sampled && view.rd_r == '0);
    a_wrong_r_drive_partition: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> axi.r_id == ID_W'(1) &&
        i_endpoint.g_txn.u_txn.watch_id == ID_W'(0));
    a_wrong_r_not_watched: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !i_endpoint.g_txn.u_txn.i_rd_tracker.r_watch);
    a_wrong_r_not_visible_internal: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !i_endpoint.g_txn.u_txn.i_rd_tracker.rsp_visible);
    a_wrong_r_not_visible_public: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !view.rd_rsp_visible);
  end
  if (MUTATION == 38) begin : g_write_id_view_guard
    a_select_first_write: assume property (
      @(posedge clk) disable iff (!rstn)
      step == 1 |-> i_endpoint.g_txn.u_txn.i_wr_b_tracker.select_now);
    a_wrong_b_does_not_complete_view: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !view.wr_rsp_complete);
    a_wrong_b_does_not_capture_view: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 4 |-> view.wr_b == '0);
    a_wrong_b_drive_partition: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> axi.b_id == ID_W'(1) &&
        i_endpoint.g_txn.u_txn.watch_id == ID_W'(0));
    a_wrong_b_not_watched: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !i_endpoint.g_txn.u_txn.i_wr_b_tracker.b_watch);
    a_wrong_b_not_visible_internal: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !i_endpoint.g_txn.u_txn.i_wr_b_tracker.rsp_visible);
    a_wrong_b_not_visible_public: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> !view.wr_rsp_visible);
  end
  if (MUTATION == 39) begin : g_write_data_view_guard
    a_select_write_waiting_for_data: assume property (
      @(posedge clk) disable iff (!rstn)
      step == 1 |-> i_endpoint.g_txn.u_txn.i_wr_b_tracker.select_now);
    a_early_b_does_not_complete_view: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 2 |-> !view.wr_rsp_complete);
    a_early_b_does_not_capture_view: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 3 |-> view.wr_b == '0);
  end

  c_view_wrong_r_handshake: cover property (
    @(posedge clk) disable iff (!rstn)
    MUTATION == 37 && step == 3 && axi.r_valid && axi.r_ready &&
    axi.r_id == ID_W'(1));
  c_view_wrong_b_handshake: cover property (
    @(posedge clk) disable iff (!rstn)
    MUTATION == 38 && step == 3 && axi.b_valid && axi.b_ready &&
    axi.b_id == ID_W'(1));
  c_view_early_b_handshake: cover property (
    @(posedge clk) disable iff (!rstn)
    MUTATION == 39 && step == 2 && axi.b_valid && axi.b_ready &&
    !view.wr_data_complete);
  c_view_sequence_reached: cover property (
    @(posedge clk) disable iff (!rstn) step == 5);
endmodule


// Preserve the parameter-exact live-channel boundary in role unit tests while
// keeping its mechanical payload/VALID/READY wiring in one place.
`define TB_BIND_ROLE_LIVE(VIEW, REQ, RSP, W_BEAT) \
  VIEW.live_aw = REQ.aw; \
  VIEW.live_aw_valid = REQ.aw_valid; \
  VIEW.live_aw_ready = RSP.aw_ready; \
  VIEW.live_w = REQ.w; \
  VIEW.live_w_valid = REQ.w_valid; \
  VIEW.live_w_ready = RSP.w_ready; \
  VIEW.live_b = RSP.b; \
  VIEW.live_b_valid = RSP.b_valid; \
  VIEW.live_b_ready = REQ.b_ready; \
  VIEW.live_ar = REQ.ar; \
  VIEW.live_ar_valid = REQ.ar_valid; \
  VIEW.live_ar_ready = RSP.ar_ready; \
  VIEW.live_r = RSP.r; \
  VIEW.live_r_valid = RSP.r_valid; \
  VIEW.live_r_ready = REQ.r_ready; \
  VIEW.channel_w_beat = W_BEAT

`define TB_CLEAR_ROLE_STATE(VIEW) \
  {VIEW.rd_select, VIEW.rd_watch_id, VIEW.rd_selected, VIEW.rd_pending, \
   VIEW.rd_completed, VIEW.rd_rank, VIEW.rd_outstanding, VIEW.rd_ar, \
   VIEW.rd_beat_idx, VIEW.rd_rsp_beat, VIEW.rd_r, VIEW.rd_beat_sampled, \
   VIEW.rd_rsp_visible, VIEW.rd_rsp_complete, VIEW.rd_rsp_wait_cycles} = '0; \
  {VIEW.wr_select, VIEW.wr_watch_id, VIEW.wr_selected, VIEW.wr_pending, \
   VIEW.wr_completed, VIEW.wr_rank, VIEW.wr_outstanding, VIEW.wr_aw, \
   VIEW.wr_data_pending, VIEW.wr_data_rank, VIEW.wr_data_complete, \
   VIEW.wr_b, VIEW.wr_rsp_visible, VIEW.wr_rsp_complete, \
   VIEW.wr_rsp_wait_cycles} = '0; \
  {VIEW.pair_select_aw, VIEW.pair_select_w, VIEW.pair_selected, \
   VIEW.pair_pending_aw, VIEW.pair_pending_w, VIEW.pair_completed, \
   VIEW.pair_rank, VIEW.pair_skew, VIEW.pair_aw, VIEW.wr_beat_idx, \
   VIEW.wr_w, VIEW.wr_beat_sampled, VIEW.pair_w_payload_idx, \
   VIEW.pair_w_payload_bit, VIEW.pair_w_payload_available, \
   VIEW.wr_data_visible, VIEW.wr_data_burst_complete, \
   VIEW.wr_data_wait_cycles} = '0

// Deterministic unit harness for the selected xbar response relation.  The
// endpoint protocol trackers are represented by their public scalar state;
// this keeps a role mutation from being mistaken for a second protocol test.
module tb_xbar_role_response_mutation #(
  parameter int MUTATION = 26
) (
  input logic clk,
  input logic rstn
);
  localparam int ADDR_W = 8;
  localparam int DATA_W = 16;
  localparam int IN_ID_W = 2;
  localparam int OUT_ID_W = IN_ID_W + 1;
  localparam int USER_W = 1;
  localparam int MAX_OUTSTANDING = 2;
  localparam int MAX_AW_AHEAD = 2;
  localparam int MAX_W_AHEAD = 2;
  localparam int MAX_BURST_LEN = 4;
  localparam int STATE_W = $clog2(
    MAX_OUTSTANDING + MAX_AW_AHEAD + MAX_W_AHEAD + 1);
  localparam int PAIR_SKEW_W = $clog2(
    ((MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD) + 1) + 1;
  localparam int W_BEAT_W = $clog2(MAX_BURST_LEN + 1);
  localparam int W_PAYLOAD_BIT_W =
    $clog2(DATA_W + DATA_W/8 + 1 + USER_W);
  localparam int OUT_B_W = OUT_ID_W + 2 + USER_W;
  localparam logic [ADDR_W-1:0] ADDR0_BASE = 8'h00;
  localparam logic [ADDR_W-1:0] ADDR1_BASE = 8'h40;
  localparam logic [ADDR_W-1:0] ADDR_MASK = 8'hc0;
  localparam logic [ADDR_W-1:0] ERROR_ADDR = 8'h80;
  localparam logic [DATA_W-1:0] ERROR_RDATA = 16'hca11;

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [DATA_W/8-1:0] strb_t;
  typedef logic [USER_W-1:0] user_t;
  typedef logic [IN_ID_W-1:0] in_id_t;
  typedef logic [OUT_ID_W-1:0] out_id_t;
  `AXI_TYPEDEF_ALL_CT(role_in_axi, in_req_t, in_rsp_t,
    addr_t, in_id_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL_CT(role_out_axi, out_req_t, out_rsp_t,
    addr_t, out_id_t, data_t, strb_t, user_t)
  localparam in_req_t IDLE_IN_REQ = '0;
  localparam in_rsp_t IDLE_IN_RSP = '0;

  logic [3:0] step;
  in_req_t s_req;
  in_rsp_t s_rsp;
  out_req_t m0_req, m1_req;
  out_rsp_t m0_rsp, m1_rsp;

  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(IN_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) s0_view ();
  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(IN_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) s1_view ();
  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) m0_view ();
  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) m1_view ();

  logic signed [PAIR_SKEW_W-1:0] s_pair_skew;
  logic signed [PAIR_SKEW_W-1:0] m0_pair_skew;
  logic [W_BEAT_W-1:0] s_channel_w_beat;
  logic [W_BEAT_W-1:0] m0_channel_w_beat;
  logic s_rd_select, s_rd_pending, s_rd_completed;
  logic [IN_ID_W-1:0] s_rd_watch_id;
  logic [7:0] s_rd_watch_beat, s_rd_rsp_beat;
  logic [STATE_W-1:0] s_rd_rank;
  logic s_wr_select, s_wr_pending, s_wr_completed;
  logic s_wr_data_pending, s_wr_data_complete;
  logic [IN_ID_W-1:0] s_wr_watch_id;
  logic [7:0] s_wr_watch_beat;
  logic [STATE_W-1:0] s_wr_rank, s_wr_data_rank;
  logic [OUT_ID_W-1:0] m0_rd_watch_id, m0_wr_watch_id;
  logic [STATE_W-1:0] m0_rd_outstanding, m0_wr_outstanding;

  wire read_case = MUTATION >= 26 && MUTATION <= 31;
  wire write_case = MUTATION >= 32 && MUTATION <= 36;
  wire read_error_case = MUTATION == 29 || MUTATION == 30;
  wire write_error_case = MUTATION == 35;
  wire s_rd_rsp_visible = s_rd_pending && s_rd_rank == 0 &&
    s_rsp.r_valid && s_rsp.r.id == s_rd_watch_id;
  wire s_wr_rsp_visible = s_wr_pending && s_wr_data_complete &&
    s_wr_rank == 0 && s_rsp.b_valid && s_rsp.b.id == s_wr_watch_id;
  // Deterministic public endpoint pair observers for the one-beat write
  // sequence below.  Source AW/W completes one cycle before output AW/W.
  wire s_pair_select_aw = write_case && step == 1;
  wire s_pair_pending_aw = write_case && step == 2;
  wire s_pair_pending_w = 1'b0;
  wire s_pair_completed = write_case && step >= 3;
  wire [STATE_W-1:0] s_pair_rank = '0;
  wire [W_PAYLOAD_BIT_W-1:0] s_pair_w_payload_idx =
    W_PAYLOAD_BIT_W'(2);
  wire s_pair_w_payload_bit = write_case && step >= 3;
  wire s_pair_w_payload_available = write_case && step >= 3;

  wire m0_pair_select_aw = write_case && !write_error_case && step == 2;
  wire m0_pair_select_w = 1'b0;
  wire m0_pair_pending_aw =
    write_case && !write_error_case && step == 3;
  wire m0_pair_pending_w = 1'b0;
  wire m0_pair_completed =
    write_case && !write_error_case && step >= 4;
  wire [STATE_W-1:0] m0_pair_rank = '0;
  wire [7:0] m0_pair_watch_beat = '0;
  wire [W_PAYLOAD_BIT_W-1:0] m0_pair_w_payload_idx =
    W_PAYLOAD_BIT_W'(2);
  wire m0_pair_w_payload_bit =
    write_case && !write_error_case && step >= 4;
  wire m0_pair_w_payload_available =
    write_case && !write_error_case && step >= 4;

  // Deterministic public endpoint-B observer model.  Case 32 first leaves
  // the selected output response stalled and live, then accepts it at step 5
  // and retains its all-zero {ID, RESP, USER} snapshot from step 6 onward.
  // Case 33 preserves the original both-BREADY-low corruption scenario.
  wire m0_wr_select = write_case && !write_error_case && step == 2;
  wire m0_wr_selected = write_case && !write_error_case && step >= 3;
  wire m0_wr_completed = MUTATION == 32 && step >= 6;
  wire m0_wr_rsp_visible = write_case && !write_error_case && step >= 4 &&
    !m0_wr_completed && m0_rsp.b_valid &&
    m0_rsp.b.id == m0_wr_watch_id;
  wire [OUT_B_W-1:0] m0_wr_b_bits = '0;

  // Adapt the deterministic scalar observer model to the same public endpoint
  // boundary used by the aggregate xbar checker.  Live channels remain split
  // from VALID/READY here, matching the production binding.
  always_comb begin
    `TB_CLEAR_ROLE_STATE(s0_view);
    `TB_BIND_ROLE_LIVE(s0_view, s_req, s_rsp, s_channel_w_beat);
    s0_view.rd_select = s_rd_select;
    s0_view.rd_watch_id = s_rd_watch_id;
    s0_view.rd_beat_idx = s_rd_watch_beat;
    s0_view.rd_pending = s_rd_pending;
    s0_view.rd_completed = s_rd_completed;
    s0_view.rd_rank = s_rd_rank;
    s0_view.rd_rsp_beat = s_rd_rsp_beat;
    s0_view.rd_rsp_visible = s_rd_rsp_visible;
    s0_view.wr_select = s_wr_select;
    s0_view.wr_watch_id = s_wr_watch_id;
    s0_view.wr_beat_idx = s_wr_watch_beat;
    s0_view.wr_pending = s_wr_pending;
    s0_view.wr_completed = s_wr_completed;
    s0_view.wr_rank = s_wr_rank;
    s0_view.wr_data_pending = s_wr_data_pending;
    s0_view.wr_data_rank = s_wr_data_rank;
    s0_view.wr_data_complete = s_wr_data_complete;
    s0_view.wr_rsp_visible = s_wr_rsp_visible;
    s0_view.pair_skew = s_pair_skew;
    s0_view.pair_select_aw = s_pair_select_aw;
    s0_view.pair_pending_aw = s_pair_pending_aw;
    s0_view.pair_pending_w = s_pair_pending_w;
    s0_view.pair_completed = s_pair_completed;
    s0_view.pair_rank = s_pair_rank;
    s0_view.pair_w_payload_idx = s_pair_w_payload_idx;
    s0_view.pair_w_payload_bit = s_pair_w_payload_bit;
    s0_view.pair_w_payload_available = s_pair_w_payload_available;

    `TB_CLEAR_ROLE_STATE(s1_view);
    `TB_BIND_ROLE_LIVE(s1_view, IDLE_IN_REQ, IDLE_IN_RSP, '0);

    `TB_CLEAR_ROLE_STATE(m0_view);
    `TB_BIND_ROLE_LIVE(m0_view, m0_req, m0_rsp, m0_channel_w_beat);
    m0_view.rd_watch_id = m0_rd_watch_id;
    m0_view.rd_outstanding = m0_rd_outstanding;
    m0_view.wr_watch_id = m0_wr_watch_id;
    m0_view.wr_outstanding = m0_wr_outstanding;
    m0_view.wr_select = m0_wr_select;
    m0_view.wr_selected = m0_wr_selected;
    m0_view.wr_completed = m0_wr_completed;
    m0_view.wr_rsp_visible = m0_wr_rsp_visible;
    m0_view.wr_b = m0_wr_b_bits;
    m0_view.pair_skew = m0_pair_skew;
    m0_view.pair_select_aw = m0_pair_select_aw;
    m0_view.pair_select_w = m0_pair_select_w;
    m0_view.pair_pending_aw = m0_pair_pending_aw;
    m0_view.pair_pending_w = m0_pair_pending_w;
    m0_view.pair_completed = m0_pair_completed;
    m0_view.pair_rank = m0_pair_rank;
    m0_view.wr_beat_idx = m0_pair_watch_beat;
    m0_view.pair_w_payload_idx = m0_pair_w_payload_idx;
    m0_view.pair_w_payload_bit = m0_pair_w_payload_bit;
    m0_view.pair_w_payload_available = m0_pair_w_payload_available;

    `TB_CLEAR_ROLE_STATE(m1_view);
    `TB_BIND_ROLE_LIVE(m1_view, m1_req, m1_rsp, '0);
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn)
      step <= '0;
    else if (step != 4'hf)
      step <= step + 1'b1;
  end

  always_comb begin
    s_req = '0;
    s_rsp = '0;
    m0_req = '0;
    m0_rsp = '0;
    m1_req = '0;
    m1_rsp = '0;

    s_req.aw.id = '0;
    s_req.aw.addr = write_error_case ? ERROR_ADDR : ADDR0_BASE;
    s_req.aw.len = 8'd0;
    s_req.aw.size = 3'd0;
    s_req.aw.burst = 2'b01;
    s_req.w.strb = 2'b01;
    s_req.w.last = 1'b1;
    s_req.ar.id = '0;
    s_req.ar.addr = read_error_case ? ERROR_ADDR : ADDR0_BASE;
    s_req.ar.len = 8'd0;
    s_req.ar.size = 3'd0;
    s_req.ar.burst = 2'b01;
    s_rsp.r.id = '0;
    s_rsp.r.last = 1'b1;

    m0_req.aw.id = {1'b0, {IN_ID_W{1'b0}}};
    m0_req.aw.addr = ADDR0_BASE;
    m0_req.aw.len = 8'd0;
    m0_req.aw.size = 3'd0;
    m0_req.aw.burst = 2'b01;
    m0_req.w.strb = 2'b01;
    m0_req.w.last = 1'b1;
    m0_req.ar.id = {1'b0, {IN_ID_W{1'b0}}};
    m0_req.ar.addr = ADDR0_BASE;
    m0_req.ar.len = 8'd0;
    m0_req.ar.size = 3'd0;
    m0_req.ar.burst = 2'b01;
    m0_rsp.r.id = {1'b0, {IN_ID_W{1'b0}}};
    m0_rsp.r.last = 1'b1;
    m0_rsp.b.id = {1'b0, {IN_ID_W{1'b0}}};

    s_pair_skew = '0;
    m0_pair_skew = '0;
    s_channel_w_beat = '0;
    m0_channel_w_beat = '0;

    s_rd_select = 1'b0;
    s_rd_pending = read_case && step >= 2;
    s_rd_completed = 1'b0;
    s_rd_watch_id = '0;
    s_rd_watch_beat = '0;
    s_rd_rsp_beat = '0;
    s_rd_rank = '0;

    s_wr_select = 1'b0;
    s_wr_pending = write_case && step >= 2;
    s_wr_completed = 1'b0;
    s_wr_watch_id = '0;
    s_wr_watch_beat = '0;
    s_wr_rank = '0;
    s_wr_data_pending = write_case && step == 2;
    s_wr_data_rank = '0;
    s_wr_data_complete = write_case && step >= 3;

    m0_rd_watch_id = {1'b0, {IN_ID_W{1'b0}}};
    m0_wr_watch_id = {1'b0, {IN_ID_W{1'b0}}};
    m0_rd_outstanding = read_case && !read_error_case && step >= 3 ?
      STATE_W'(1) : '0;
    m0_wr_outstanding = write_case && !write_error_case && step >= 3 &&
      !(MUTATION == 32 && step >= 6) ? STATE_W'(1) : '0;

    if (read_case) begin
      if (step == 1) begin
        s_rd_select = 1'b1;
        s_req.ar_valid = 1'b1;
        s_rsp.ar_ready = 1'b1;
      end
      if (!read_error_case && step == 2) begin
        m0_req.ar_valid = 1'b1;
        m0_rsp.ar_ready = 1'b1;
      end

      case (MUTATION)
        26, 27, 28: if (step >= 3) begin
          s_rsp.r_valid = 1'b1;
          s_req.r_ready = 1'b0;
          m0_rsp.r_valid = 1'b1;
          m0_req.r_ready = 1'b0;
          if (MUTATION == 27)
            s_rsp.r.data[0] = 1'b1;
          if (MUTATION == 28)
            m0_rsp.r.last = 1'b0;
        end
        29: if (step >= 2) begin
          s_rsp.r_valid = 1'b1;
          s_req.r_ready = 1'b0;
          s_rsp.r.data = ERROR_RDATA;
          s_rsp.r.resp = axi_pkg::RESP_OKAY;
        end
        30: if (step >= 2) begin
          s_rsp.r_valid = 1'b1;
          s_req.r_ready = 1'b0;
          s_rsp.r.data = '0;
          s_rsp.r.resp = axi_pkg::RESP_DECERR;
        end
        31: begin
          if (step == 3 || step == 4) begin
            s_rsp.r_valid = 1'b1;
            s_req.r_ready = step == 4;
            s_rsp.r.id = IN_ID_W'(1);
            m0_rsp.r_valid = 1'b1;
            m0_req.r_ready = step == 4;
            // Flip the source prefix while retaining the watched low ID.
            m0_rsp.r.id = {1'b1, {IN_ID_W{1'b0}}};
          end else if (step >= 5) begin
            s_rsp.r_valid = 1'b1;
            s_req.r_ready = 1'b0;
            s_rsp.r.last = 1'b0;
          end
        end
        default: begin end
      endcase
    end

    if (write_case) begin
      if (step == 1) begin
        s_wr_select = 1'b1;
        s_req.aw_valid = 1'b1;
        s_rsp.aw_ready = 1'b1;
      end
      if (step == 2) begin
        s_req.w_valid = 1'b1;
        s_rsp.w_ready = 1'b1;
        s_pair_skew = PAIR_SKEW_W'(1);
        if (!write_error_case) begin
          m0_req.aw_valid = 1'b1;
          m0_rsp.aw_ready = 1'b1;
        end
      end
      if (!write_error_case && step == 3) begin
        m0_req.w_valid = 1'b1;
        m0_rsp.w_ready = 1'b1;
        m0_pair_skew = PAIR_SKEW_W'(1);
      end

      case (MUTATION)
        32, 33: if (step >= 4) begin
          s_rsp.b_valid = 1'b1;
          s_req.b_ready = 1'b0;
          // Case 32 is stalled at step 4, accepted at step 5, then represented
          // by the endpoint snapshot.  Case 33 remains live and stalled.
          m0_rsp.b_valid = MUTATION == 33 || step <= 5;
          m0_req.b_ready = MUTATION == 32 && step == 5;
          if (MUTATION == 33)
            s_rsp.b.resp = axi_pkg::RESP_DECERR;
        end
        34: if (step >= 3) begin
          s_rsp.b_valid = 1'b1;
          s_req.b_ready = 1'b0;
          m0_rsp.b_valid = 1'b1;
          m0_req.b_ready = 1'b0;
        end
        35: if (step >= 3) begin
          s_rsp.b_valid = 1'b1;
          s_req.b_ready = 1'b0;
          s_rsp.b.resp = axi_pkg::RESP_OKAY;
        end
        36: begin
          if (step == 4 || step == 5) begin
            s_rsp.b_valid = 1'b1;
            s_req.b_ready = step == 5;
            s_rsp.b.id = IN_ID_W'(1);
            m0_rsp.b_valid = 1'b1;
            m0_req.b_ready = step == 5;
            m0_rsp.b.id = {1'b1, {IN_ID_W{1'b0}}};
          end else if (step >= 6) begin
            s_rsp.b_valid = 1'b1;
            s_req.b_ready = 1'b0;
          end
        end
        default: begin end
      endcase
    end
  end

  fv_axi_xbar_source_role #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .IN_ID_W(IN_ID_W), .OUT_ID_W(OUT_ID_W), .USER_W(USER_W),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_OUTPUT_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD), .MAX_W_AHEAD(MAX_W_AHEAD),
    .MAX_OUTPUT_AW_AHEAD(MAX_AW_AHEAD),
    .MAX_OUTPUT_W_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_PROGRESS(1'b0),
    .ADDR0_BASE(ADDR0_BASE), .ADDR1_BASE(ADDR1_BASE),
    .ADDR_MASK(ADDR_MASK), .DEFAULT_ENABLE(2'b00),
    .DEFAULT_DEST(2'b00), .ERROR_RDATA(ERROR_RDATA)
  ) i_role (
    .clk(clk), .rstn(rstn), .source(1'b0),
    .s0_view(s0_view), .s1_view(s1_view),
    .m0_view(m0_view), .m1_view(m1_view)
  );

  if (MUTATION >= 26 && MUTATION <= 31) begin : g_read_partition
    a_watch_read: assume property (@(posedge clk) !i_role.watch_write);
    a_watch_read_route: assume property (@(posedge clk)
      i_role.watch_route == (read_error_case ? 2'd2 : 2'd0));
    a_watch_read_payload: assume property (@(posedge clk)
      i_role.watch_payload_bit == 4);
  end
  if (MUTATION >= 32 && MUTATION <= 36) begin : g_write_partition
    a_watch_write: assume property (@(posedge clk) i_role.watch_write);
    a_watch_write_route: assume property (@(posedge clk)
      i_role.watch_route == (write_error_case ? 2'd2 : 2'd0));
    a_watch_write_payload: assume property (@(posedge clk)
      i_role.watch_payload_bit == 2);
  end

  if (MUTATION == 31) begin : g_wrong_r_guard
    a_wrong_r_offer_is_not_selected: assert property (
      @(posedge clk) disable iff (!rstn)
      (step == 3 || step == 4) |->
        !i_role.i_read.selected_s_r && !i_role.i_read.selected_m_r);
    a_wrong_r_handshake_preserves_target: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 5 |-> i_role.i_read.m_rsp_pending &&
        i_role.i_read.m_rsp_rank == 0 &&
        !i_role.i_read.m_beat_sampled && !i_role.i_read.m_rsp_completed);
  end
  if (MUTATION == 36) begin : g_wrong_b_guard
    a_wrong_b_offer_is_not_selected: assert property (
      @(posedge clk) disable iff (!rstn)
      (step == 4 || step == 5) |->
        !i_role.i_write.selected_s_b && !i_role.i_write.selected_m_b);
    a_wrong_b_handshake_preserves_target: assert property (
      @(posedge clk) disable iff (!rstn)
      step == 6 |-> i_role.i_write.m_b_pending &&
        i_role.i_write.m_b_rank == 0 &&
        !i_role.i_write.m_b_sampled);
  end

  c_ready_low_read_offer: cover property (
    @(posedge clk) disable iff (!rstn)
    read_case && ((read_error_case && step == 2) ||
      (!read_error_case && step == 3)) &&
    s_rsp.r_valid && !s_req.r_ready);
  c_ready_low_write_offer: cover property (
    @(posedge clk) disable iff (!rstn)
    write_case && ((write_error_case && step == 3) ||
      (!write_error_case && step == 4)) &&
    s_rsp.b_valid && !s_req.b_ready);
  c_same_edge_wlast_b_offer: cover property (
    @(posedge clk) disable iff (!rstn)
    MUTATION == 34 && step == 3 && m0_req.w_valid && m0_rsp.w_ready &&
    m0_req.w.last && s_rsp.b_valid && !s_req.b_ready &&
    m0_rsp.b_valid && !m0_req.b_ready);
  c_endpoint_b_shadow_live: cover property (
    @(posedge clk) disable iff (!rstn)
    MUTATION == 32 && step == 4 && m0_wr_rsp_visible &&
    !m0_wr_completed && s_rsp.b_valid && !s_req.b_ready);
  c_endpoint_b_shadow_stored: cover property (
    @(posedge clk) disable iff (!rstn)
    MUTATION == 32 && step == 6 && !m0_wr_rsp_visible &&
    m0_wr_completed && s_rsp.b_valid && !s_req.b_ready);
  c_role_sequence_reached: cover property (
    @(posedge clk) disable iff (!rstn) step == 7);
endmodule

`undef TB_BIND_ROLE_LIVE
`undef TB_CLEAR_ROLE_STATE
