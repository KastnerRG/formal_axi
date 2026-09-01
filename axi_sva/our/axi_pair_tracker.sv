// Two-sided selected AW/completed-W tracker.  One arbitrary beat is sampled
// for WSTRB legality, so state is independent of outstanding count and grows
// only logarithmically with maximum burst length.
module `MODNAME_PAIR_TRACKER #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int MAX_A_AHEAD = 8,
  parameter int MAX_B_AHEAD = 8,
  parameter int CONFIG_MAX_A_AHEAD = 4,
  parameter int CONFIG_MAX_B_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16
) (
  input logic clk,
  input logic rstn,
  input logic aw_hsk,
  input logic [ADDR_W-1:0] aw_addr,
  input logic [7:0] aw_len,
  input logic [2:0] aw_size,
  input logic [1:0] aw_burst,
  input logic w_valid,
  input logic w_hsk,
  input logic [DATA_W/8-1:0] w_strb,
  input logic w_last
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int STRB_W = DATA_W/8;
  localparam int RANK_MAX = (MAX_A_AHEAD > MAX_B_AHEAD) ? MAX_A_AHEAD : MAX_B_AHEAD;
  localparam int RANK_W = (RANK_MAX < 2) ? 1 : $clog2(RANK_MAX+1);
  localparam int SKEW_W = RANK_W + 1;
  localparam int WATCH_BEAT_W = (MAX_BURST_LEN < 2) ? 1 : $clog2(MAX_BURST_LEN);
  localparam int AGE_W = (MAX_WRITE_DATA_DELAY < 2) ?
    1 : $clog2(MAX_WRITE_DATA_DELAY+1);

  (* anyseq *) logic select_aw, select_w;
  (* anyconst *) logic [WATCH_BEAT_W-1:0] watch_beat;
  logic selected, pending_aw, pending_w, completed;
  logic [RANK_W-1:0] rank;
  logic signed [SKEW_W-1:0] skew;
  logic [AGE_W-1:0] wr_data_age;

  logic [ADDR_W-1:0] watched_aw_addr;
  logic [7:0] watched_aw_len;
  logic [2:0] watched_aw_size;
  logic [1:0] watched_aw_burst;
  logic [8:0] watched_w_beats;
  logic [STRB_W-1:0] watched_w_strb;

  logic [8:0] current_w_beat;
  logic [STRB_W-1:0] current_w_watch_strb;
  wire w_complete = w_hsk && w_last;
  wire [8:0] current_w_beats = current_w_beat + 9'd1;
  wire [STRB_W-1:0] completed_watch_strb =
    (current_w_beat == watch_beat) ? w_strb : current_w_watch_strb;
  wire wr_visible = pending_aw && rank == 0 && w_valid;

  s_watch_beat_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_beat));
  c_watch_beat_range: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    watch_beat < MAX_BURST_LEN);
  s_select_one: assume property (!(select_aw && select_w));
  s_select_aw_occurrence: assume property (select_aw |-> aw_hsk && !selected && skew >= 0);
  s_select_w_occurrence: assume property (select_w |-> w_complete && !selected && skew <= 0);
  s_select_once: assume property (selected |-> !select_aw && !select_w);

`ifdef MASTER
  // These constrain only an external Manager.  MAX_A/B_AHEAD below are the
  // larger internal tracking capacities allowed on a DUT output.
  c_max_aw_ahead: assume property (aw_hsk && !w_complete |-> skew < CONFIG_MAX_A_AHEAD);
  c_max_w_ahead: assume property (w_complete && !aw_hsk |-> skew > -CONFIG_MAX_B_AHEAD);
`endif

  x_a_ahead_bound: `TXN_SOURCE property (aw_hsk && !w_complete |-> skew < MAX_A_AHEAD);
  x_b_ahead_bound: `TXN_SOURCE property (w_complete && !aw_hsk |-> skew > -MAX_B_AHEAD);
  x_w_burst_bound: `TXN_SOURCE property (w_hsk |-> current_w_beat < MAX_BURST_LEN);

  // An AW/W skew bound limits buffered bursts, but cannot force WVALID.  This
  // optional policy bounds each required W beat after its AW is accepted.
  generate if (ENABLE_WRITE_DATA_PROGRESS) begin : g_write_data_progress
    x_write_data_progress: `TXN_SOURCE property (
      pending_aw |-> wr_visible || wr_data_age < MAX_WRITE_DATA_DELAY);
  end endgenerate

  x_w_last_exact_after_aw: `TXN_SOURCE property (pending_aw && w_complete && rank == 0 |->
      current_w_beats == {1'b0, watched_aw_len} + 9'd1);
  x_w_last_exact_after_w: `TXN_SOURCE property (pending_w && aw_hsk && rank == 0 |->
      watched_w_beats == {1'b0, aw_len} + 9'd1);
  x_w_last_exact_simultaneous_aw: `TXN_SOURCE property (
    select_aw && w_complete && skew == 0 |->
      current_w_beats == {1'b0, aw_len} + 9'd1);
  x_w_last_exact_simultaneous_w: `TXN_SOURCE property (
    select_w && aw_hsk && skew == 0 |->
      current_w_beats == {1'b0, aw_len} + 9'd1);

  // Because watch_beat is arbitrary, these four properties cover every beat
  // without generating one proof target or one stored WSTRB per beat.
  x_wstrb_after_aw: `TXN_SOURCE property (pending_aw && w_complete && rank == 0 && watch_beat < current_w_beats |->
        wstrb_valid(watched_aw_addr, watched_aw_size, watched_aw_burst,
                    watched_aw_len, watch_beat, completed_watch_strb, DATA_W));
  x_wstrb_after_w: `TXN_SOURCE property (pending_w && aw_hsk && rank == 0 && watch_beat < watched_w_beats |->
        wstrb_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                    watched_w_strb, DATA_W));
  x_wstrb_simultaneous_aw: `TXN_SOURCE property (
      select_aw && w_complete && skew == 0 && watch_beat < current_w_beats |->
        wstrb_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                    completed_watch_strb, DATA_W));
  x_wstrb_simultaneous_w: `TXN_SOURCE property (
      select_w && aw_hsk && skew == 0 && watch_beat < current_w_beats |->
        wstrb_valid(aw_addr, aw_size, aw_burst, aw_len, watch_beat,
                    completed_watch_strb, DATA_W));

  c_select_a: cover property (select_aw);
  c_select_b: cover property (select_w);
  c_w_before_aw: cover property (skew < 0);
  c_aw_before_w: cover property (skew > 0);
  c_complete: cover property (completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      skew <= '0;
      selected <= 1'b0;
      pending_aw <= 1'b0;
      pending_w <= 1'b0;
      completed <= 1'b0;
      rank <= '0;
      current_w_beat <= '0;
      watched_aw_addr <= '0;
      watched_aw_len <= '0;
      watched_aw_size <= '0;
      watched_aw_burst <= '0;
      watched_w_beats <= '0;
      watched_w_strb <= '0;
      current_w_watch_strb <= '0;
      wr_data_age <= '0;
    end else begin
      case ({aw_hsk, w_complete})
        2'b10: skew <= skew + 1;
        2'b01: skew <= skew - 1;
        default: skew <= skew;
      endcase

      if (w_hsk && current_w_beat == watch_beat)
        current_w_watch_strb <= w_strb;
      if (w_complete)
        current_w_beat <= '0;
      else if (w_hsk)
        current_w_beat <= current_w_beat + 1'b1;

      if (select_aw) begin
        selected <= 1'b1;
        watched_aw_addr <= aw_addr;
        watched_aw_len <= aw_len;
        watched_aw_size <= aw_size;
        watched_aw_burst <= aw_burst;
        wr_data_age <= '0;
        if (w_complete && skew == 0) begin
          completed <= 1'b1;
        end else begin
          pending_aw <= 1'b1;
          rank <= skew - (w_complete ? 1'b1 : 1'b0);
        end
      end else if (select_w) begin
        selected <= 1'b1;
        watched_w_beats <= current_w_beats;
        watched_w_strb <= completed_watch_strb;
        if (aw_hsk && skew == 0) begin
          completed <= 1'b1;
        end else begin
          pending_w <= 1'b1;
          rank <= -skew - (aw_hsk ? 1'b1 : 1'b0);
        end
      end else if (pending_aw && w_complete) begin
        if (rank == 0) begin
          pending_aw <= 1'b0;
          completed <= 1'b1;
        end else begin
          rank <= rank - 1'b1;
        end
      end else if (pending_w && aw_hsk) begin
        if (rank == 0) begin
          pending_w <= 1'b0;
          completed <= 1'b1;
        end else begin
          rank <= rank - 1'b1;
        end
      end


      if (pending_aw) begin
        if (wr_visible || (w_hsk && rank == 0))
          wr_data_age <= '0;
        else if (wr_data_age < MAX_WRITE_DATA_DELAY)
          wr_data_age <= wr_data_age + 1'b1;
      end
    end
  end
endmodule

