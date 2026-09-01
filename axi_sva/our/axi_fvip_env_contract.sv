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
  parameter int MAX_WRITE_DATA_DELAY = 16
) (
  input logic clk,
  input logic rstn,
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
  // their address, age, strobe, and burst dimensions are module parameters.
  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [AGE_W-1:0] age_t;
  typedef logic [MAX_BURST_LEN-1:0][STRB_W-1:0] burst_strb_t;
  typedef struct packed {
    addr_t addr;
    axi_pkg::len_t len;
    axi_pkg::size_t size;
    axi_pkg::burst_t burst;
    age_t age;
  } aw_entry_t;
  typedef struct packed {
    logic [8:0] beats;
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
  logic [8:0] current_w_beat;
  logic [W_COUNT_W-1:0] w_count;

  always_comb begin
    completed_w.beats = current_w_beat + 9'd1;
    completed_w.strb = current_w_strb;
    for (int beat = 0; beat < MAX_BURST_LEN; beat++)
      if (beat == current_w_beat)
        completed_w.strb[beat] = axi.w_strb;
  end

  wire join_write = aw_count != 0 && w_count != 0;

  a_aw_capacity: assume property (aw_hsk |-> aw_count < AW_DEPTH || join_write);
  a_w_capacity: assume property (w_complete |-> w_count < W_DEPTH || join_write);
  a_w_burst_bound: assume property (w_hsk |-> current_w_beat < MAX_BURST_LEN);
  a_wlast_exact: assume property (join_write |-> w_q[0].beats == {1'b0, aw_q[0].len} + 9'd1);

  for (genvar beat = 0; beat < MAX_BURST_LEN; beat++) begin : g_wstrb
    a_wstrb: assume property (join_write && beat < w_q[0].beats |->
        wstrb_valid(aw_q[0].addr, aw_q[0].size, aw_q[0].burst,
                    aw_q[0].len, beat, w_q[0].strb[beat], DATA_W));
  end

  if (ENABLE_WRITE_DATA_PROGRESS) begin : g_write_progress
    for (genvar slot = 0; slot < AW_DEPTH; slot++) begin : g_slot
      // This deterministic environment contract uses the stronger, simple
      // form: the corresponding complete W burst must join within the bound.
      a_write_data_delay: assume property (slot < aw_count |-> aw_q[slot].age < MAX_WRITE_DATA_DELAY);
    end
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      aw_count <= '0;
      w_count <= '0;
      current_w_beat <= '0;
      foreach (aw_q[entry])
        aw_q[entry].age <= '0;
    end else begin
      foreach (aw_q[entry])
        if (entry < aw_count && aw_q[entry].age < MAX_WRITE_DATA_DELAY)
          aw_q[entry].age <= aw_q[entry].age + 1'b1;

      if (join_write)
        for (int entry = 0; entry < AW_DEPTH-1; entry++)
          aw_q[entry] <= aw_q[entry+1];
      if (aw_hsk)
        aw_q[aw_count - (join_write ? 1'b1 : 1'b0)] <= '{
          addr: axi.aw_addr,
          len: axi.aw_len,
          size: axi.aw_size,
          burst: axi.aw_burst,
          age: '0
        };
      case ({aw_hsk, join_write})
        2'b10: aw_count <= aw_count + 1'b1;
        2'b01: aw_count <= aw_count - 1'b1;
        default: aw_count <= aw_count;
      endcase

      if (w_hsk && current_w_beat < MAX_BURST_LEN)
        current_w_strb[current_w_beat] <= axi.w_strb;
      if (w_complete)
        current_w_beat <= '0;
      else if (w_hsk)
        current_w_beat <= current_w_beat + 1'b1;

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
    age_t age;
  } read_entry_t;
  typedef struct packed {
    id_t id;
    age_t age;
  } write_entry_t;

  wire ar_hsk = axi.ar_valid && axi.ar_ready;
  wire r_hsk = axi.r_valid && axi.r_ready;
  wire aw_hsk = axi.aw_valid && axi.aw_ready;
  wire w_complete = axi.w_valid && axi.w_ready && axi.w_last;
  wire b_hsk = axi.b_valid && axi.b_ready;

  read_entry_t read_q [0:TRACK_DEPTH-1];
  logic [COUNT_W-1:0] read_count;
  integer r_match;
  always_comb begin
    r_match = -1;
    for (int slot = TRACK_DEPTH-1; slot >= 0; slot--)
      if (slot < read_count && read_q[slot].id == axi.r_id)
        r_match = slot;
  end
  wire r_has_request = r_match >= 0;
  wire r_pop = r_hsk && r_has_request && axi.r_last;

  a_r_has_ar: assume property (axi.r_valid |-> r_has_request);
  a_rlast_exact: assume property (axi.r_valid && r_has_request |->
      axi.r_last == (read_q[r_match].beat == read_q[r_match].len));

  if (ENABLE_RESPONSE_PROGRESS) begin : g_read_progress
    for (genvar slot = 0; slot < TRACK_DEPTH; slot++) begin : g_slot
      a_read_response_delay: assume property (slot < read_count |->
          (axi.r_valid && r_match == slot) ||
          read_q[slot].age < MAX_RESPONSE_DELAY);
    end
  end

  id_t aw_q [0:AW_DEPTH-1];
  logic [AW_COUNT_W-1:0] aw_count;
  localparam int W_COUNT_W = (W_DEPTH < 2) ? 1 : $clog2(W_DEPTH + 1);
  logic [W_COUNT_W-1:0] w_count;
  wire join_write = aw_count != 0 && w_count != 0;

  write_entry_t write_q [0:TRACK_DEPTH-1];
  logic [COUNT_W-1:0] write_count;
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
  wire b_consumes_join = b_hsk && !b_matches_queue && b_matches_join;

  a_b_has_completed_write: assume property (axi.b_valid |-> b_has_write);

  if (ENABLE_RESPONSE_PROGRESS) begin : g_write_progress
    for (genvar slot = 0; slot < TRACK_DEPTH; slot++) begin : g_slot
      a_write_response_delay: assume property (slot < write_count |->
          (axi.b_valid && b_match == slot) ||
          write_q[slot].age < MAX_RESPONSE_DELAY);
    end
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      read_count <= '0;
      aw_count <= '0;
      w_count <= '0;
      write_count <= '0;
      foreach (read_q[entry]) begin
        read_q[entry].age <= '0;
        write_q[entry].age <= '0;
      end
    end else begin
      foreach (read_q[entry]) begin
        if (entry < read_count && read_q[entry].age < MAX_RESPONSE_DELAY)
          read_q[entry].age <= read_q[entry].age + 1'b1;
        if (entry < write_count && write_q[entry].age < MAX_RESPONSE_DELAY)
          write_q[entry].age <= write_q[entry].age + 1'b1;
      end

      if (r_hsk && r_has_request) begin
        read_q[r_match].age <= '0;
        if (!axi.r_last)
          read_q[r_match].beat <= read_q[r_match].beat + 1'b1;
      end
      if (r_pop)
        for (int entry = 0; entry < TRACK_DEPTH-1; entry++)
          if (entry >= r_match)
            read_q[entry] <= read_q[entry+1];
      if (ar_hsk && read_count - (r_pop ? 1'b1 : 1'b0) < TRACK_DEPTH)
        read_q[read_count - (r_pop ? 1'b1 : 1'b0)] <= '{
          id: axi.ar_id,
          len: axi.ar_len,
          beat: '0,
          age: '0
        };
      case ({ar_hsk && read_count < TRACK_DEPTH, r_pop})
        2'b10: read_count <= read_count + 1'b1;
        2'b01: read_count <= read_count - 1'b1;
        default: read_count <= read_count;
      endcase

      if (join_write)
        for (int entry = 0; entry < AW_DEPTH-1; entry++)
          aw_q[entry] <= aw_q[entry+1];
      if (aw_hsk && aw_count - (join_write ? 1'b1 : 1'b0) < AW_DEPTH)
        aw_q[aw_count - (join_write ? 1'b1 : 1'b0)] <= axi.aw_id;
      case ({aw_hsk && aw_count < AW_DEPTH, join_write})
        2'b10: aw_count <= aw_count + 1'b1;
        2'b01: aw_count <= aw_count - 1'b1;
        default: aw_count <= aw_count;
      endcase
      case ({w_complete && w_count < W_DEPTH, join_write})
        2'b10: w_count <= w_count + 1'b1;
        2'b01: w_count <= w_count - 1'b1;
        default: w_count <= w_count;
      endcase

      if (b_pop)
        for (int entry = 0; entry < TRACK_DEPTH-1; entry++)
          if (entry >= b_match)
            write_q[entry] <= write_q[entry+1];
      if (join_write && !b_consumes_join &&
          write_count - (b_pop ? 1'b1 : 1'b0) < TRACK_DEPTH)
        write_q[write_count - (b_pop ? 1'b1 : 1'b0)] <= '{
          id: aw_q[0],
          age: '0
        };
      case ({join_write && !b_consumes_join && write_count < TRACK_DEPTH,
             b_pop})
        2'b10: write_count <= write_count + 1'b1;
        2'b01: write_count <= write_count - 1'b1;
        default: write_count <= write_count;
      endcase
    end
  end
endmodule
