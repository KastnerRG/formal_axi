// Constant-state occurrence bookkeeping shared by FIFO and routed-stream
// checkers. Callers own capacity policy; properties stay in the thin shells.
module fv_stream_occurrence_core #(
  parameter int WIDTH = 32,
  parameter int MAX_PENDING = 4,
  parameter bit EMPTY_SELECT_COMPLETES = 1'b0,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 32,
  localparam int COUNT_W = (MAX_PENDING < 2) ? 1 : $clog2(MAX_PENDING + 1),
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1)
) (
  input logic clk, rstn, select_now, s_hsk, m_hsk,
  input logic [WIDTH-1:0] s_data,
  output logic selected, pending,
  output logic completed,
  output logic [WIDTH-1:0] watched_data,
  output logic [COUNT_W-1:0] rank, occupancy,
  output logic [AGE_W-1:0] age
);
  always_comb completed = selected && !pending;

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      selected <= 1'b0;
      pending <= 1'b0;
      watched_data <= '0;
      rank <= '0;
      occupancy <= '0;
      age <= '0;
    end else begin
      case ({s_hsk, m_hsk})
        2'b10: occupancy <= occupancy + 1'b1;
        2'b01: occupancy <= occupancy - 1'b1;
        default: occupancy <= occupancy;
      endcase

      if (select_now) begin
        selected <= 1'b1;
        watched_data <= s_data;
        age <= '0;
        if (EMPTY_SELECT_COMPLETES && occupancy == 0 && m_hsk) begin
          pending <= 1'b0;
          rank <= '0;
        end else begin
          pending <= 1'b1;
          rank <= occupancy - ((m_hsk && occupancy != 0) ? 1'b1 : 1'b0);
        end
      end else if (pending && m_hsk) begin
        if (rank == 0) begin
          pending <= 1'b0;
        end else begin
          rank <= rank - 1'b1;
        end
      end

      if (pending && ENABLE_PROGRESS && age < MAX_DELAY)
        age <= age + 1'b1;
    end
  end
endmodule

// Select either side of two ordered streams and wait for the same ordinal
// occurrence on the other side.  balance is the continuously maintained
// prefix difference; remaining freezes the selected distance and ignores
// later events on the selected side.
module fv_ordered_pair_core #(
  parameter int MAX_A_AHEAD = 4,
  parameter int MAX_B_AHEAD = 4,
  localparam int BALANCE_W = $clog2(((MAX_A_AHEAD > MAX_B_AHEAD) ? MAX_A_AHEAD : MAX_B_AHEAD) + 1) + 1,
  localparam int REMAINING_W = BALANCE_W + 1,
  localparam int RANK_W = BALANCE_W
) (
  input logic clk, rstn,
  input logic select_a, select_b,
  input logic a_hsk, b_hsk,
  output logic selected,
  output logic pending_a, pending_b, completed,
  output logic [RANK_W-1:0] rank,
  output logic signed [BALANCE_W-1:0] balance
);
  // One extra bit preserves the selection transition even on an already
  // illegal boundary balance.  The shell still reports the bound violation,
  // while this observer remains deterministic instead of wrapping polarity.
  logic signed [REMAINING_W-1:0] remaining;
  wire signed [REMAINING_W-1:0] extended_balance = {balance[BALANCE_W-1], balance};

  always_comb begin
    pending_a = selected && remaining > 0;
    pending_b = selected && remaining < 0;
    completed = selected && remaining == 0;
    if (remaining > 0) rank = RANK_W'($unsigned(remaining - REMAINING_W'(1)));
    else if (remaining < 0) rank = RANK_W'($unsigned(-remaining - REMAINING_W'(1)));
    else rank = '0;
  end

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      selected <= 1'b0;
      remaining <= '0;
      balance <= '0;
    end else begin
      case ({a_hsk, b_hsk})
        2'b10: balance <= balance + BALANCE_W'(1);
        2'b01: balance <= balance - BALANCE_W'(1);
        default: balance <= balance;
      endcase

      if (select_a) begin
        selected <= 1'b1;
        remaining <= extended_balance + REMAINING_W'(1) - REMAINING_W'(b_hsk);
      end else if (select_b) begin
        selected <= 1'b1;
        remaining <= extended_balance - REMAINING_W'(1) + REMAINING_W'(a_hsk);
      end else if (remaining > 0 && b_hsk) begin
        remaining <= remaining - REMAINING_W'(1);
      end else if (remaining < 0 && a_hsk) begin
        remaining <= remaining + REMAINING_W'(1);
      end
    end
  end
endmodule

// Production transparent ready/valid FIFO checker. The exact bounded
// reference queue lives under fvip_validation/reference_models.
module fv_fifo_tracker #(
  parameter int WIDTH = 32,
  parameter int MAX_OCCUPANCY = 4,
  parameter bit ALLOW_BYPASS = 1'b0,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 100
) (
  input logic clk, rstn,
  input logic [WIDTH-1:0] s_data,
  input logic s_hsk,
  input logic [WIDTH-1:0] m_data,
  input logic m_hsk
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int COUNT_W = (MAX_OCCUPANCY < 2) ? 1 : $clog2(MAX_OCCUPANCY + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);
  (* anyseq *) logic select_now;
  logic selected, pending, completed;
  logic [WIDTH-1:0] watched_data;
  logic [COUNT_W-1:0] rank, occupancy;
  logic [AGE_W-1:0] age;

  fv_stream_occurrence_core #(
    .WIDTH(WIDTH), .MAX_PENDING(MAX_OCCUPANCY),
    // Preserve the historical mutation-state transition even though the
    // registered shell separately rejects an empty output handshake.
    .EMPTY_SELECT_COMPLETES(1'b1),
    .ENABLE_PROGRESS(ENABLE_PROGRESS), .MAX_DELAY(MAX_DELAY)
  ) i_occurrence (.*);

  s_select_handshake: assume property (select_now |-> s_hsk && !selected);
  s_select_once: assume property (selected |-> !select_now);

  generate if (ALLOW_BYPASS) begin : g_conservation_bypass
    a_no_phantom: assert property (m_hsk |-> occupancy != 0 || s_hsk);
  end else begin : g_conservation_registered
    a_no_phantom: assert property (m_hsk |-> occupancy != 0);
  end endgenerate
  a_no_overflow: assert property (s_hsk |-> occupancy != MAX_OCCUPANCY || m_hsk);
  a_watched_integrity: assert property (
    pending && m_hsk && rank == 0 |-> m_data == watched_data);
  generate if (ALLOW_BYPASS) begin : g_bypass
    a_selected_bypass: assert property (
      select_now && occupancy == 0 && m_hsk |-> m_data == s_data);
  end endgenerate
  generate if (ENABLE_PROGRESS) begin : g_progress
    a_watched_progress: assert property (pending |-> age < MAX_DELAY);
  end endgenerate

  c_select: cover property (select_now);
  c_select_behind_data: cover property (select_now && occupancy != 0);
  c_watched_complete: cover property (completed);
endmodule

// Selected-occurrence conservation for one routed, ordered AXI stream. The
// caller supplies one source/destination/ID partition and one payload bit.
module fv_xbar_stream_tracker #(
  parameter int WIDTH = 32,
  parameter int MAX_PENDING = 4,
  parameter bit ALLOW_BYPASS = 1'b1,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 32,
  parameter int BIT_W = (WIDTH < 2) ? 1 : $clog2(WIDTH)
) (
  input logic clk, rstn, select_class, select_now,
  input logic [WIDTH-1:0] s_data,
  input logic s_valid, s_hsk,
  input logic [WIDTH-1:0] m_data,
  input logic m_valid, m_hsk,
  input logic [BIT_W-1:0] watch_bit,
  output logic selected_m_hsk, selected_m_offer,
  output logic selected_pending, selected_completed
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int COUNT_W = (MAX_PENDING < 2) ? 1 : $clog2(MAX_PENDING + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);
  logic selected, pending, completed;
  logic [0:0] watched_data;
  logic [COUNT_W-1:0] rank, occupancy;
  logic [AGE_W-1:0] age;
  wire [0:0] selected_s_data = watch_bit < WIDTH ? s_data[watch_bit] : 1'b0;
  wire watched_data_bit = watched_data[0];

  fv_stream_occurrence_core #(
    .WIDTH(1), .MAX_PENDING(MAX_PENDING),
    .EMPTY_SELECT_COMPLETES(ALLOW_BYPASS),
    .ENABLE_PROGRESS(ENABLE_PROGRESS), .MAX_DELAY(MAX_DELAY)
  ) i_occurrence (
    .clk(clk), .rstn(rstn), .select_now(select_now),
    .s_data(selected_s_data), .s_hsk(s_hsk), .m_hsk(m_hsk),
    .selected(selected), .pending(pending), .completed(completed),
    .watched_data(watched_data), .rank(rank), .occupancy(occupancy), .age(age)
  );

  assign selected_pending = pending;
  assign selected_completed = completed;
  s_select_handshake: assume property (select_now |-> s_hsk && !selected);
  s_select_once: assume property (selected |-> !select_now);
  assign selected_m_hsk = m_hsk && ((pending && rank == 0) || (ALLOW_BYPASS && select_now && occupancy == 0));
  wire stored_selected_m_offer = m_valid && pending && rank == 0;
  assign selected_m_offer = stored_selected_m_offer || (ALLOW_BYPASS && m_valid && select_now && occupancy == 0);
  wire live_bypass_m_offer = ALLOW_BYPASS && m_valid && occupancy == 0 && s_valid;
  wire checked_m_offer = stored_selected_m_offer || live_bypass_m_offer;

  if (ALLOW_BYPASS) begin : g_bypass_conservation
    a_no_phantom: assert property (m_hsk |-> occupancy != 0 || s_hsk);
  end else begin : g_registered_conservation
    a_no_phantom: assert property (m_hsk |-> occupancy != 0);
  end
  a_no_overflow: assert property (
    s_hsk |-> occupancy != MAX_PENDING || m_hsk);
  a_no_phantom_offer: assert property (
    m_valid |-> occupancy != 0 || (ALLOW_BYPASS && s_valid));
  a_tracker_pending_rank: assert property (pending |-> occupancy > rank);
  a_selected_integrity_class0: assert property (
    checked_m_offer && !select_class && watch_bit < WIDTH |->
      m_data[watch_bit] ==
        (stored_selected_m_offer ? watched_data_bit : s_data[watch_bit]));
  a_selected_integrity_class1: assert property (
    checked_m_offer && select_class && watch_bit < WIDTH |->
      m_data[watch_bit] ==
        (stored_selected_m_offer ? watched_data_bit : s_data[watch_bit]));
  if (ENABLE_PROGRESS) begin : g_progress
    a_selected_progress: assert property (pending |-> age < MAX_DELAY);
  end

  c_select: cover property (select_now);
  c_stalled_selected_offer: cover property (stored_selected_m_offer && !m_hsk);
  c_stalled_exact_selected_offer: cover property (selected_m_offer && !m_hsk);
  c_stalled_live_bypass_offer: cover property (live_bypass_m_offer && !m_hsk);
  if (MAX_PENDING > 1) begin : g_rank_cover
    c_select_with_rank: cover property (select_now && occupancy != 0);
  end
  c_complete: cover property (completed);
endmodule
