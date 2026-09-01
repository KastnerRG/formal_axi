`timescale 1ns/1ps

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
module tb_transaction_mutation #(
  parameter int MUTATION = 0
) (
  input logic clk,
  input logic rstn
);
  localparam int ADDR_W = 8;
  localparam int DATA_W = 16;
  localparam int ID_W = 2;

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
    if (!rstn) step <= '0;
    else if (step != 5'h1f) step <= step + 1'b1;
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
        b_valid = step == 4;
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
        b_valid = step == 1;
        aw_valid = step == 3;
        w_valid = step == 4;
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
        b_valid = step == 4 || step == 6;
      end
      13: begin
        aw_valid = step == 1;
      end
      14: begin
        aw_valid = step == 1;
        w_valid = step == 2;
      end
      default: begin end
    endcase
  end

  // Exact bounded reference model.  This is deliberately instantiated only
  // in the verifier-validation harness, never in production FIFO closure.
  fv_axi_transaction_oracle #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
    .MAX_READ_OUTSTANDING(2), .MAX_WRITE_OUTSTANDING(2),
    .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2), .MAX_BURST_LEN(4)
  ) i_oracle (.*);

  // Response-side mutations are checked with Manager polarity; source-side
  // WLAST/WSTRB mutations use Subordinate polarity so those rules are asserts.
  generate if (MUTATION == 4 || MUTATION == 5 || MUTATION == 13) begin : g_source
    s_axi_transaction_fvip #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
      .MAX_READ_OUTSTANDING(2), .MAX_WRITE_OUTSTANDING(2),
      .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2), .MAX_BURST_LEN(4),
      .ENABLE_WRITE_DATA_PROGRESS(1'b1), .MAX_WRITE_DATA_DELAY(6)
    ) i_txn (.clk(clk), .rstn(rstn), .axi(axi));
  end else begin : g_response
    m_axi_transaction_fvip #(
      .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
      .MAX_READ_OUTSTANDING(2), .MAX_WRITE_OUTSTANDING(2),
      .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2), .MAX_BURST_LEN(4),
      .ENABLE_RESPONSE_PROGRESS(1'b1), .MAX_RESPONSE_DELAY(6)
    ) i_txn (.clk(clk), .rstn(rstn), .axi(axi));
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
        step == 5 |-> i_txn.i_wr_b_tracker.pending &&
          i_txn.i_wr_b_tracker.b_rank == 0 &&
          i_txn.i_wr_b_tracker.outstanding == 1);
    end
  end endgenerate

  cover property (@(posedge clk) disable iff (!rstn) step == 6);
endmodule
