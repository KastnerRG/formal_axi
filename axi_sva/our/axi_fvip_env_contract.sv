// Deterministic contracts for the unconstrained endpoint environment.
//
// Smart selectors are ideal for DUT assertions but cannot be the only source
// of assumptions: an environment could simply avoid selecting a bad
// occurrence.  These bounded models therefore constrain every environment
// transaction.  They are not DUT scoreboards and expose no proof result.

module axi_fvip_manager_env_contract #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16,
  localparam int BURST_COUNT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1)
) (
  input logic clk,
  input logic rstn,
  input logic [BURST_COUNT_W-1:0] current_w_beat,
  AXI_BUS.Monitor axi
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int AW_DEPTH = MAX_OUTSTANDING + MAX_AW_AHEAD;
  localparam int W_DEPTH = MAX_OUTSTANDING + MAX_W_AHEAD;
  localparam int AW_COUNT_W = (AW_DEPTH < 2) ? 1 : $clog2(AW_DEPTH + 1);
  localparam int W_COUNT_W = (W_DEPTH < 2) ? 1 : $clog2(W_DEPTH + 1);
  localparam int AGE_W = (MAX_WRITE_DATA_DELAY < 2) ?
    1 : $clog2(MAX_WRITE_DATA_DELAY + 1);
  localparam int STRB_W = DATA_W / 8;

  // PULP supplies the AXI field types.  The queue entries stay local because
  // their address, strobe, and burst dimensions are module parameters.
  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [AGE_W-1:0] age_t;
  typedef logic [MAX_BURST_LEN-1:0][STRB_W-1:0] burst_strb_t;
  typedef struct packed {
    addr_t addr;
    axi_pkg::len_t len;
    axi_pkg::size_t size;
    axi_pkg::burst_t burst;
  } aw_entry_t;
  typedef struct packed {
    logic [BURST_COUNT_W-1:0] beats;
    burst_strb_t strb;
  } w_entry_t;

  wire aw_hsk = axi.aw_valid && axi.aw_ready;
  wire w_hsk = axi.w_valid && axi.w_ready;
  wire w_complete = w_hsk && axi.w_last;

  aw_entry_t aw_q [0:AW_DEPTH-1];
  logic [AW_COUNT_W-1:0] aw_count;

  w_entry_t w_q [0:W_DEPTH-1];
  burst_strb_t current_w_strb;
  w_entry_t completed_w;
  logic [W_COUNT_W-1:0] w_count;
  age_t write_data_age;

  always_comb begin
    completed_w.beats = current_w_beat + 1'b1;
    completed_w.strb = current_w_strb;
    for (int beat = 0; beat < MAX_BURST_LEN; beat++)
      if (beat == current_w_beat)
        completed_w.strb[beat] = axi.w_strb;
  end

  wire join_write = aw_count != 0 && w_count != 0;
  // Completed W bursts pair with AWs in order.  When there are more accepted
  // AWs than completed W bursts, exactly one next burst is eligible to supply
  // data.  Timing only that burst avoids duplicating one timer per AW.
  wire write_data_pending = w_count < aw_count;

  // Match the current incomplete W burst without waiting for DUT-owned
  // READY.  Completed unmatched W bursts occupy the first w_count positions
  // in AW order, so the current burst maps to aw_q[w_count].  At count parity
  // the next offered AW supplies its metadata even before its handshake.  If
  // W is farther ahead, that live AW instead pairs with completed w_q entry
  // aw_count; current-burst metadata is not known yet.
  wire current_w_has_queued_aw = w_count < aw_count;
  wire current_w_has_live_aw =
    w_count == aw_count && axi.aw_valid;
  wire completed_w_has_live_aw =
    aw_count < w_count && axi.aw_valid;

  // Capacity is an obligation on the environment's offered transfer.  Using
  // VALID rather than a handshake prevents these assumptions from disabling
  // DUT-owned READY when a queue is full.
  a_aw_capacity: assume property (
    axi.aw_valid |-> aw_count < AW_DEPTH || join_write);
  a_w_capacity: assume property (
    axi.w_valid && axi.w_last |-> w_count < W_DEPTH || join_write);
  a_w_burst_bound: assume property (
    axi.w_valid |-> current_w_beat < MAX_BURST_LEN);

  // The deterministic Manager contract checks every known AW/W association
  // at offer time.  Position remains constrained even between W offers: a
  // partial W burst cannot pass its future terminal beat before a late AW
  // reveals AWLEN.  WLAST and the full WSTRB vector are checked whenever the
  // current beat is offered, independently of WREADY.
  a_current_w_position_queued_aw: assume property (
    current_w_has_queued_aw |->
      current_w_beat <= aw_q[w_count].len);
  a_current_wlast_queued_aw: assume property (
    current_w_has_queued_aw && axi.w_valid |->
      axi.w_last == (current_w_beat == aw_q[w_count].len));
  a_current_wstrb_queued_aw: assume property (
    current_w_has_queued_aw && axi.w_valid |->
      wstrb_valid(aw_q[w_count].addr, aw_q[w_count].size,
                  aw_q[w_count].burst, aw_q[w_count].len,
                  current_w_beat, axi.w_strb, DATA_W));

  a_current_w_position_live_aw: assume property (
    current_w_has_live_aw |->
      current_w_beat <= axi.aw_len);
  a_current_wlast_live_aw: assume property (
    current_w_has_live_aw && axi.w_valid |->
      axi.w_last == (current_w_beat == axi.aw_len));
  a_current_wstrb_live_aw: assume property (
    current_w_has_live_aw && axi.w_valid |->
      wstrb_valid(axi.aw_addr, axi.aw_size, axi.aw_burst, axi.aw_len,
                  current_w_beat, axi.w_strb, DATA_W));

  // When AW metadata becomes known after one or more W handshakes, validate
  // the already captured prefix immediately.  A live AW offered behind one
  // or more completed W bursts likewise validates the completed packet it
  // would pair with, without depending on AWREADY.
  for (genvar beat = 0; beat < MAX_BURST_LEN; beat++) begin : g_offer_wstrb
    a_current_w_prefix_queued_aw: assume property (
      current_w_has_queued_aw && beat < current_w_beat |->
        wstrb_valid(aw_q[w_count].addr, aw_q[w_count].size,
                    aw_q[w_count].burst, aw_q[w_count].len, beat,
                    current_w_strb[beat], DATA_W));
    a_current_w_prefix_live_aw: assume property (
      current_w_has_live_aw && beat < current_w_beat |->
        wstrb_valid(axi.aw_addr, axi.aw_size, axi.aw_burst, axi.aw_len,
                    beat, current_w_strb[beat], DATA_W));
    a_completed_w_live_aw: assume property (
      completed_w_has_live_aw && beat < w_q[aw_count].beats |->
        wstrb_valid(axi.aw_addr, axi.aw_size, axi.aw_burst, axi.aw_len,
                    beat, w_q[aw_count].strb[beat], DATA_W));
  end

  a_completed_wlast_live_aw: assume property (
    completed_w_has_live_aw |->
      w_q[aw_count].beats == {1'b0, axi.aw_len} + 1'b1);

  // Retain the queued retrospective checks for W-before-AW packets whose
  // metadata was not available on any of their W offer edges.
  a_wlast_exact: assume property (join_write |->
      w_q[0].beats == {1'b0, aw_q[0].len} + 1'b1);

  for (genvar beat = 0; beat < MAX_BURST_LEN; beat++) begin : g_wstrb
    a_wstrb: assume property (join_write && beat < w_q[0].beats |->
        wstrb_valid(aw_q[0].addr, aw_q[0].size, aw_q[0].burst,
                    aw_q[0].len, beat, w_q[0].strb[beat], DATA_W));
  end

  if (ENABLE_WRITE_DATA_PROGRESS) begin : g_write_progress
    // Bound availability of each required W beat, not its handshake.  Once
    // WVALID is offered the environment has done its part; a stalled WREADY
    // owned by the DUT must not consume this deadline.
    a_write_data_delay: assume property (write_data_pending |->
        axi.w_valid || write_data_age < MAX_WRITE_DATA_DELAY);
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      aw_count <= '0;
      w_count <= '0;
      write_data_age <= '0;
    end else begin
      if (ENABLE_WRITE_DATA_PROGRESS) begin
        if (!write_data_pending || axi.w_valid)
          write_data_age <= '0;
        else if (write_data_age < MAX_WRITE_DATA_DELAY)
          write_data_age <= write_data_age + 1'b1;
      end

      if (join_write)
        for (int entry = 0; entry < AW_DEPTH-1; entry++)
          aw_q[entry] <= aw_q[entry+1];
      if (aw_hsk)
        aw_q[aw_count - (join_write ? 1'b1 : 1'b0)] <= '{
          addr: axi.aw_addr,
          len: axi.aw_len,
          size: axi.aw_size,
          burst: axi.aw_burst
        };
      case ({aw_hsk, join_write})
        2'b10: aw_count <= aw_count + 1'b1;
        2'b01: aw_count <= aw_count - 1'b1;
        default: aw_count <= aw_count;
      endcase

      if (w_hsk && current_w_beat < MAX_BURST_LEN)
        current_w_strb[current_w_beat] <= axi.w_strb;
      if (join_write)
        for (int entry = 0; entry < W_DEPTH-1; entry++)
          w_q[entry] <= w_q[entry+1];
      if (w_complete)
        w_q[w_count - (join_write ? 1'b1 : 1'b0)] <= completed_w;
      case ({w_complete, join_write})
        2'b10: w_count <= w_count + 1'b1;
        2'b01: w_count <= w_count - 1'b1;
        default: w_count <= w_count;
      endcase
    end
  end
endmodule


module axi_fvip_subordinate_env_contract #(
  parameter int ID_W = 4,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16
) (
  input logic clk,
  input logic rstn,
  AXI_BUS.Monitor axi
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int TRACK_DEPTH = MAX_OUTSTANDING + 1;
  localparam int AW_DEPTH = MAX_OUTSTANDING + MAX_AW_AHEAD + 1;
  localparam int W_DEPTH = MAX_OUTSTANDING + MAX_W_AHEAD + 1;
  localparam int COUNT_W = (TRACK_DEPTH < 2) ? 1 : $clog2(TRACK_DEPTH + 1);
  localparam int AW_COUNT_W = (AW_DEPTH < 2) ? 1 : $clog2(AW_DEPTH + 1);
  localparam int AGE_W = (MAX_RESPONSE_DELAY < 2) ?
    1 : $clog2(MAX_RESPONSE_DELAY + 1);

  typedef logic [ID_W-1:0] id_t;
  typedef logic [AGE_W-1:0] age_t;
  typedef struct packed {
    id_t id;
    axi_pkg::len_t len;
    axi_pkg::len_t beat;
  } read_entry_t;
  typedef struct packed {
    id_t id;
  } write_entry_t;

  wire ar_hsk = axi.ar_valid && axi.ar_ready;
  wire r_hsk = axi.r_valid && axi.r_ready;
  wire aw_hsk = axi.aw_valid && axi.aw_ready;
  wire w_complete = axi.w_valid && axi.w_ready && axi.w_last;
  wire b_hsk = axi.b_valid && axi.b_ready;

  read_entry_t read_q [0:TRACK_DEPTH-1];
  read_entry_t read_q_next [0:TRACK_DEPTH-1];
  logic [COUNT_W-1:0] read_count, read_count_next;
  integer r_match;
  always_comb begin
    r_match = -1;
    for (int slot = TRACK_DEPTH-1; slot >= 0; slot--)
      if (slot < read_count && read_q[slot].id == axi.r_id)
        r_match = slot;
  end
  wire r_has_request = r_match >= 0;
  wire r_pop = r_hsk && r_has_request && axi.r_last;
  wire read_push = ar_hsk && (read_count < TRACK_DEPTH || r_pop);
  wire r_stalled = axi.r_valid && !axi.r_ready;

  // Compute the complete queue transition explicitly.  The progress timer
  // below can therefore distinguish a surviving head from the new head
  // exposed by physical compaction and simultaneous pop/push.
  always_comb begin
    for (int entry = 0; entry < TRACK_DEPTH; entry++)
      read_q_next[entry] = read_q[entry];

    if (r_hsk && r_has_request && !axi.r_last)
      read_q_next[r_match].beat = read_q[r_match].beat + 1'b1;
    if (r_pop)
      for (int entry = 0; entry < TRACK_DEPTH-1; entry++)
        if (entry >= r_match)
          read_q_next[entry] = read_q[entry+1];
    if (read_push)
      read_q_next[read_count - (r_pop ? 1'b1 : 1'b0)] = '{
        id: axi.ar_id,
        len: axi.ar_len,
        beat: '0
      };

    case ({read_push, r_pop})
      2'b10: read_count_next = read_count + 1'b1;
      2'b01: read_count_next = read_count - 1'b1;
      default: read_count_next = read_count;
    endcase
  end

  // The oldest global request is always a legal per-ID response head, so slot
  // zero is the unique scheduled burst without storing a selector.  Other IDs
  // may interleave before its deadline, but cannot starve this burst forever.
  age_t read_response_age, read_response_age_next;
  wire read_head_pending = read_count != 0;
  wire read_head_visible =
    read_head_pending && axi.r_valid && r_match == 0;

  // A visible head beat serves the availability obligation independently of
  // READY.  A non-final beat keeps the same burst at the head and restarts its
  // per-beat timer.  A final beat exposes the post-pop head with age zero.
  always_comb begin
    read_response_age_next = read_response_age;
    if (ENABLE_RESPONSE_PROGRESS) begin
      if (!read_head_pending || read_head_visible)
        read_response_age_next = '0;
      else if (!r_stalled &&
               read_response_age < MAX_RESPONSE_DELAY)
        read_response_age_next = read_response_age + 1'b1;
    end else begin
      read_response_age_next = '0;
    end
  end

  a_r_has_ar: assume property (axi.r_valid |-> r_has_request);
  a_rlast_exact: assume property (axi.r_valid && r_has_request |->
      axi.r_last == (read_q[r_match].beat == read_q[r_match].len));

  if (ENABLE_RESPONSE_PROGRESS) begin : g_read_progress
    a_read_response_delay: assume property (read_head_pending |->
        read_head_visible ||
        read_response_age < MAX_RESPONSE_DELAY);
  end

  id_t aw_q [0:AW_DEPTH-1];
  logic [AW_COUNT_W-1:0] aw_count;
  localparam int W_COUNT_W = (W_DEPTH < 2) ? 1 : $clog2(W_DEPTH + 1);
  logic [W_COUNT_W-1:0] w_count;
  wire join_write = aw_count != 0 && w_count != 0;
  wire aw_push = aw_hsk && (aw_count < AW_DEPTH || join_write);
  wire w_push = w_complete && (w_count < W_DEPTH || join_write);

  write_entry_t write_q [0:TRACK_DEPTH-1];
  write_entry_t write_q_next [0:TRACK_DEPTH-1];
  logic [COUNT_W-1:0] write_count, write_count_next;
  integer b_match;
  always_comb begin
    b_match = -1;
    for (int slot = TRACK_DEPTH-1; slot >= 0; slot--)
      if (slot < write_count && write_q[slot].id == axi.b_id)
        b_match = slot;
  end
  wire b_matches_queue = b_match >= 0;
  wire b_matches_join = join_write && axi.b_id == aw_q[0];
  wire b_has_write = b_matches_queue || b_matches_join;
  wire b_pop = b_hsk && b_matches_queue;
  wire b_consumes_join =
    b_hsk && !b_matches_queue && b_matches_join;
  wire write_push = join_write && !b_consumes_join &&
                    (write_count < TRACK_DEPTH || b_pop);
  wire b_stalled = axi.b_valid && !axi.b_ready;

  always_comb begin
    for (int entry = 0; entry < TRACK_DEPTH; entry++)
      write_q_next[entry] = write_q[entry];

    if (b_pop)
      for (int entry = 0; entry < TRACK_DEPTH-1; entry++)
        if (entry >= b_match)
          write_q_next[entry] = write_q[entry+1];
    if (write_push)
      write_q_next[write_count - (b_pop ? 1'b1 : 1'b0)] = '{
        id: aw_q[0]
      };

    case ({write_push, b_pop})
      2'b10: write_count_next = write_count + 1'b1;
      2'b01: write_count_next = write_count - 1'b1;
      default: write_count_next = write_count;
    endcase
  end

  // As on R, the global queue head is the one bounded-service obligation.
  // Responses for later, different IDs may interleave before the deadline.
  age_t write_response_age, write_response_age_next;
  wire write_head_pending = write_count != 0;
  wire write_head_visible =
    write_head_pending && axi.b_valid && b_match == 0;

  always_comb begin
    write_response_age_next = write_response_age;
    if (ENABLE_RESPONSE_PROGRESS) begin
      if (!write_head_pending || write_head_visible)
        write_response_age_next = '0;
      else if (!b_stalled &&
               write_response_age < MAX_RESPONSE_DELAY)
        write_response_age_next = write_response_age + 1'b1;
    end else begin
      write_response_age_next = '0;
    end
  end

  a_b_has_completed_write: assume property (axi.b_valid |-> b_has_write);

  if (ENABLE_RESPONSE_PROGRESS) begin : g_write_progress
    a_write_response_delay: assume property (write_head_pending |->
        write_head_visible ||
        write_response_age < MAX_RESPONSE_DELAY);
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      read_count <= '0;
      aw_count <= '0;
      w_count <= '0;
      write_count <= '0;
      read_response_age <= '0;
      write_response_age <= '0;
    end else begin
      for (int entry = 0; entry < TRACK_DEPTH; entry++) begin
        read_q[entry] <= read_q_next[entry];
        write_q[entry] <= write_q_next[entry];
      end
      read_count <= read_count_next;
      write_count <= write_count_next;
      read_response_age <= read_response_age_next;
      write_response_age <= write_response_age_next;

      if (join_write)
        for (int entry = 0; entry < AW_DEPTH-1; entry++)
          aw_q[entry] <= aw_q[entry+1];
      if (aw_push)
        aw_q[aw_count - (join_write ? 1'b1 : 1'b0)] <= axi.aw_id;
      case ({aw_push, join_write})
        2'b10: aw_count <= aw_count + 1'b1;
        2'b01: aw_count <= aw_count - 1'b1;
        default: aw_count <= aw_count;
      endcase
      case ({w_push, join_write})
        2'b10: w_count <= w_count + 1'b1;
        2'b01: w_count <= w_count - 1'b1;
        default: w_count <= w_count;
      endcase
    end
  end
endmodule
