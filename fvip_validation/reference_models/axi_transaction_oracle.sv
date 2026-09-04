// Validation-only exact bounded AXI4 transaction reference model.
// State scales with the configured bounds; do not use this in DUT closure.
// Bounded AXI4 normal-transaction oracle for one link.  It uses global bounded
// slots and searches the oldest matching ID, so different IDs may interleave
// while same-ID responses remain ordered.
module fv_axi_transaction_oracle #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int MAX_READ_OUTSTANDING = 4,
  parameter int MAX_WRITE_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8
) (
  input logic clk,
  input logic rstn,
  input logic aw_valid, aw_ready,
  input logic [ID_W-1:0] aw_id,
  input logic [ADDR_W-1:0] aw_addr,
  input logic [7:0] aw_len,
  input logic [2:0] aw_size,
  input logic [1:0] aw_burst,
  input logic w_valid, w_ready,
  input logic [DATA_W/8-1:0] w_strb,
  input logic w_last,
  input logic b_valid, b_ready,
  input logic [ID_W-1:0] b_id,
  input logic ar_valid, ar_ready,
  input logic [ID_W-1:0] ar_id,
  input logic [7:0] ar_len,
  input logic r_valid, r_ready,
  input logic [ID_W-1:0] r_id,
  input logic r_last
);
  import pkg_axi_fvip::*;

  localparam int RD_COUNT_W = (MAX_READ_OUTSTANDING < 2) ? 1 : $clog2(MAX_READ_OUTSTANDING+1);
  localparam int WR_COUNT_W = (MAX_WRITE_OUTSTANDING < 2) ? 1 : $clog2(MAX_WRITE_OUTSTANDING+1);
  // A pass-through component can add its channel buffering to the configured
  // input skew.  These slots are implementation capacity, not an AXI rule.
  localparam int AW_TRACK_DEPTH = MAX_AW_AHEAD + MAX_WRITE_OUTSTANDING;
  localparam int W_TRACK_DEPTH = MAX_W_AHEAD + MAX_WRITE_OUTSTANDING;
  localparam int AW_COUNT_W = $clog2(AW_TRACK_DEPTH+1);
  localparam int WQ_COUNT_W = $clog2(W_TRACK_DEPTH+1);
  localparam int STRB_W = DATA_W/8;

  wire aw_hsk = aw_valid && aw_ready;
  wire w_hsk = w_valid && w_ready;
  wire b_hsk = b_valid && b_ready;
  wire ar_hsk = ar_valid && ar_ready;
  wire r_hsk = r_valid && r_ready;

  // AR -> R: oldest matching global slot, with beat progress stored per slot.
  logic [ID_W-1:0] rd_id [0:MAX_READ_OUTSTANDING-1];
  logic [7:0] rd_len [0:MAX_READ_OUTSTANDING-1];
  logic [7:0] rd_beat [0:MAX_READ_OUTSTANDING-1];
  logic [RD_COUNT_W-1:0] rd_count;
  integer r_match;
  always_comb begin
    r_match = -1;
    for (int slot = MAX_READ_OUTSTANDING-1; slot >= 0; slot--)
      if (slot < rd_count && rd_id[slot] == r_id)
        r_match = slot;
  end
  wire r_has_request = r_match >= 0;
  wire r_expected_last = r_has_request && rd_beat[r_match] == rd_len[r_match];
  wire r_pop = r_hsk && r_has_request && r_last;

  x_ar_capacity: assert property (@(posedge clk) disable iff (!rstn)
    ar_hsk |-> rd_count < MAX_READ_OUTSTANDING || r_pop);
  x_r_has_ar: assert property (@(posedge clk) disable iff (!rstn)
    r_valid |-> r_has_request);
  x_r_last_exact: assert property (@(posedge clk) disable iff (!rstn)
    r_valid && r_has_request |-> r_last == r_expected_last);

  c_read_request: cover property (@(posedge clk) disable iff (!rstn) ar_hsk);
  c_read_response: cover property (@(posedge clk) disable iff (!rstn) r_hsk && r_last);
  c_read_max_occupancy: cover property (@(posedge clk) disable iff (!rstn)
    rd_count == MAX_READ_OUTSTANDING);
  c_read_interleave: cover property (@(posedge clk) disable iff (!rstn)
    r_hsk && !r_last ##[1:8] r_hsk && r_id != $past(r_id));

  // AW <-> W: two queues capture whichever side arrives first.  W entries are
  // complete bursts because AXI4 has no WID and write-data bursts cannot
  // interleave.
  logic [ID_W-1:0] awq_id [0:AW_TRACK_DEPTH-1];
  logic [ADDR_W-1:0] awq_addr [0:AW_TRACK_DEPTH-1];
  logic [7:0] awq_len [0:AW_TRACK_DEPTH-1];
  logic [2:0] awq_size [0:AW_TRACK_DEPTH-1];
  logic [1:0] awq_burst [0:AW_TRACK_DEPTH-1];
  logic [AW_COUNT_W-1:0] awq_count;

  logic [8:0] wq_beats [0:W_TRACK_DEPTH-1];
  logic [STRB_W-1:0] wq_strb [0:W_TRACK_DEPTH-1][0:MAX_BURST_LEN-1];
  logic [WQ_COUNT_W-1:0] wq_count;
  logic [8:0] current_w_beat;
  logic [STRB_W-1:0] current_w_strb [0:MAX_BURST_LEN-1];

  wire join_write = awq_count != 0 && wq_count != 0;
  wire w_complete = w_hsk && w_last;

`ifdef MASTER
  // Configuration assumptions apply to the external Manager only.  They are
  // not promoted to AXI guarantees on a checked DUT output.
  c_max_aw_ahead: assume property (@(posedge clk) disable iff (!rstn)
    aw_hsk |-> awq_count < MAX_AW_AHEAD || join_write);
  c_max_w_ahead: assume property (@(posedge clk) disable iff (!rstn)
    w_complete |-> wq_count < MAX_W_AHEAD || join_write);
`endif
  x_aw_tracking_capacity: assert property (@(posedge clk) disable iff (!rstn)
    aw_hsk |-> awq_count < AW_TRACK_DEPTH || join_write);
  x_w_tracking_capacity: assert property (@(posedge clk) disable iff (!rstn)
    w_complete |-> wq_count < W_TRACK_DEPTH || join_write);
  x_w_burst_bound: assert property (@(posedge clk) disable iff (!rstn)
    w_hsk |-> current_w_beat < MAX_BURST_LEN);
  x_w_last_exact: assert property (@(posedge clk) disable iff (!rstn)
    join_write |-> wq_beats[0] == {1'b0, awq_len[0]} + 9'd1);

  for (genvar beat = 0; beat < MAX_BURST_LEN; beat++) begin : g_wstrb
    x_wstrb: assert property (@(posedge clk) disable iff (!rstn)
      join_write && beat < wq_beats[0] |->
        wstrb_valid(awq_addr[0], awq_size[0], awq_burst[0], awq_len[0],
                    beat, wq_strb[0][beat], DATA_W));
  end

  c_w_before_aw: cover property (@(posedge clk) disable iff (!rstn)
    wq_count != 0 && awq_count == 0);
  c_aw_before_w: cover property (@(posedge clk) disable iff (!rstn)
    awq_count != 0 && wq_count == 0);
  c_write_join: cover property (@(posedge clk) disable iff (!rstn) join_write);

  // Completed (AW+W) -> B: again search the oldest matching ID, allowing
  // different-ID response reordering but no phantom/duplicate/wrong-ID B.
  logic [ID_W-1:0] wr_id [0:MAX_WRITE_OUTSTANDING-1];
  logic [WR_COUNT_W-1:0] wr_count;
  integer b_match;
  always_comb begin
    b_match = -1;
    for (int slot = MAX_WRITE_OUTSTANDING-1; slot >= 0; slot--)
      if (slot < wr_count && wr_id[slot] == b_id)
        b_match = slot;
  end
  wire [ID_W-1:0] joined_id = awq_id[0];
  wire b_matches_queue = b_match >= 0;
  // join_write is formed only from AW and completed-W entries that were
  // already accepted before this sampled edge.  A response may consume that
  // just-joined write without waiting an extra cycle for wr_id[] to update.
  // Prefer an older queued match of the same ID so the bypass cannot violate
  // AXI's same-ID response ordering; different IDs may still reorder.
  wire b_matches_join = join_write && b_id == joined_id;
  wire b_has_write = b_matches_queue || b_matches_join;
  wire b_pop = b_hsk && b_matches_queue;
  wire b_consumes_join =
    b_hsk && !b_matches_queue && b_matches_join;
  wire write_push = join_write && !b_consumes_join &&
                    (wr_count < MAX_WRITE_OUTSTANDING || b_pop);

  // The production selected-occurrence helpers are intentionally not
  // instantiated here; this module is the independent exact comparison.

  x_write_outstanding_bound: assert property (@(posedge clk) disable iff (!rstn)
    join_write && !b_consumes_join |->
      wr_count < MAX_WRITE_OUTSTANDING || b_pop);
  x_b_has_completed_write: assert property (@(posedge clk) disable iff (!rstn)
    b_valid |-> b_has_write);

  c_b_response: cover property (@(posedge clk) disable iff (!rstn) b_hsk);
  c_b_join_bypass: cover property (@(posedge clk) disable iff (!rstn)
    b_consumes_join);
  c_b_queue_pop_push: cover property (@(posedge clk) disable iff (!rstn)
    b_pop && write_push);
  c_b_different_id_join_reorder: cover property (
    @(posedge clk) disable iff (!rstn)
    b_consumes_join && wr_count != 0);
  c_write_max_occupancy: cover property (@(posedge clk) disable iff (!rstn)
    wr_count == MAX_WRITE_OUTSTANDING);

  integer entry, lane;
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      rd_count <= '0;
      awq_count <= '0;
      wq_count <= '0;
      current_w_beat <= '0;
      wr_count <= '0;
    end else begin
      // Read queue removal, append, and per-slot beat progress.
      if (r_hsk && r_has_request && !r_last)
        rd_beat[r_match] <= rd_beat[r_match] + 1'b1;
      if (r_pop)
        for (entry = 0; entry < MAX_READ_OUTSTANDING-1; entry = entry + 1)
          if (entry >= r_match) begin
            rd_id[entry] <= rd_id[entry+1];
            rd_len[entry] <= rd_len[entry+1];
            rd_beat[entry] <= rd_beat[entry+1];
          end
      if (ar_hsk) begin
        rd_id[rd_count - (r_pop ? 1'b1 : 1'b0)] <= ar_id;
        rd_len[rd_count - (r_pop ? 1'b1 : 1'b0)] <= ar_len;
        rd_beat[rd_count - (r_pop ? 1'b1 : 1'b0)] <= '0;
      end
      case ({ar_hsk, r_pop})
        2'b10: rd_count <= rd_count + 1'b1;
        2'b01: rd_count <= rd_count - 1'b1;
        default: rd_count <= rd_count;
      endcase

      // AW unpaired queue.
      if (join_write)
        for (entry = 0; entry < AW_TRACK_DEPTH-1; entry = entry + 1) begin
          awq_id[entry] <= awq_id[entry+1];
          awq_addr[entry] <= awq_addr[entry+1];
          awq_len[entry] <= awq_len[entry+1];
          awq_size[entry] <= awq_size[entry+1];
          awq_burst[entry] <= awq_burst[entry+1];
        end
      if (aw_hsk) begin
        awq_id[awq_count - (join_write ? 1'b1 : 1'b0)] <= aw_id;
        awq_addr[awq_count - (join_write ? 1'b1 : 1'b0)] <= aw_addr;
        awq_len[awq_count - (join_write ? 1'b1 : 1'b0)] <= aw_len;
        awq_size[awq_count - (join_write ? 1'b1 : 1'b0)] <= aw_size;
        awq_burst[awq_count - (join_write ? 1'b1 : 1'b0)] <= aw_burst;
      end
      case ({aw_hsk, join_write})
        2'b10: awq_count <= awq_count + 1'b1;
        2'b01: awq_count <= awq_count - 1'b1;
        default: awq_count <= awq_count;
      endcase

      // Current W burst and completed-W queue.
      if (w_hsk && current_w_beat < MAX_BURST_LEN)
        current_w_strb[current_w_beat] <= w_strb;
      if (w_complete)
        current_w_beat <= '0;
      else if (w_hsk)
        current_w_beat <= current_w_beat + 1'b1;
      if (join_write)
        for (entry = 0; entry < W_TRACK_DEPTH-1; entry = entry + 1) begin
          wq_beats[entry] <= wq_beats[entry+1];
          for (lane = 0; lane < MAX_BURST_LEN; lane = lane + 1)
            wq_strb[entry][lane] <= wq_strb[entry+1][lane];
        end
      if (w_complete) begin
        wq_beats[wq_count - (join_write ? 1'b1 : 1'b0)] <= current_w_beat + 1'b1;
        for (lane = 0; lane < MAX_BURST_LEN; lane = lane + 1)
          wq_strb[wq_count - (join_write ? 1'b1 : 1'b0)][lane] <=
            (lane == current_w_beat) ? w_strb : current_w_strb[lane];
      end
      case ({w_complete, join_write})
        2'b10: wq_count <= wq_count + 1'b1;
        2'b01: wq_count <= wq_count - 1'b1;
        default: wq_count <= wq_count;
      endcase

      // Completed write response queue.
      if (b_pop)
        for (entry = 0; entry < MAX_WRITE_OUTSTANDING-1; entry = entry + 1)
          if (entry >= b_match)
            wr_id[entry] <= wr_id[entry+1];
      if (write_push)
        wr_id[wr_count - (b_pop ? 1'b1 : 1'b0)] <= joined_id;
      case ({write_push, b_pop})
        2'b10: wr_count <= wr_count + 1'b1;
        2'b01: wr_count <= wr_count - 1'b1;
        default: wr_count <= wr_count;
      endcase
    end
  end
endmodule
