// Selected-occurrence conservation for one routed, ordered AXI stream.
//
// The caller filters the stream to one source port, one destination port, and
// one arbitrary ID domain.  This tracker then proves that the filtered input
// sequence is neither fabricated, lost, duplicated, reordered, nor changed.
// It intentionally knows nothing about AXI channel ownership or DUT hierarchy.
module fv_xbar_stream_tracker #(
  parameter int WIDTH = 32,
  parameter int MAX_PENDING = 4,
  parameter bit ALLOW_BYPASS = 1'b1,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 32,
  parameter int BIT_W = (WIDTH < 2) ? 1 : $clog2(WIDTH)
) (
  input logic clk,
  input logic rstn,
  // A stable caller-provided proof partition.  It changes no tracker state;
  // separate integrity targets let formal prune either multiplexed stream.
  input logic select_class,
  input logic select_now,
  input logic [WIDTH-1:0] s_data,
  input logic s_valid,
  input logic s_hsk,
  input logic [WIDTH-1:0] m_data,
  input logic m_valid,
  input logic m_hsk,
  input logic [BIT_W-1:0] watch_bit,
  output logic selected_m_hsk,
  output logic selected_m_offer,
  output logic selected_pending,
  output logic selected_completed
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int COUNT_W = (MAX_PENDING < 2) ? 1 : $clog2(MAX_PENDING + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);
  logic selected, pending, completed;
  logic watched_data_bit;
  logic [COUNT_W-1:0] rank;
  logic [COUNT_W-1:0] occupancy;
  logic [AGE_W-1:0] age;

  // Public lifecycle view for role consumers.  These are aliases of the
  // existing selected-occurrence state, not additional proof state.
  assign selected_pending = pending;
  assign selected_completed = completed;

  s_select_handshake: assume property (select_now |-> s_hsk && !selected);
  s_select_once: assume property (selected |-> !select_now);
  assign selected_m_hsk = m_hsk &&
    ((pending && rank == 0) ||
      (ALLOW_BYPASS && select_now && occupancy == 0));
  wire stored_selected_m_offer = m_valid && pending && rank == 0;
  // Exact READY-independent offer for the selected occurrence.  This differs
  // from live_bypass_m_offer below: only the source occurrence selected by
  // select_now may use the empty-queue bypass arm.
  assign selected_m_offer = stored_selected_m_offer ||
    (ALLOW_BYPASS && m_valid && select_now && occupancy == 0);
  wire live_bypass_m_offer =
    ALLOW_BYPASS && m_valid && occupancy == 0 && s_valid;
  wire checked_m_offer = stored_selected_m_offer || live_bypass_m_offer;

  if (ALLOW_BYPASS) begin : g_bypass_conservation
    a_no_phantom: assert property (m_hsk |-> occupancy != 0 || s_hsk);
  end else begin : g_registered_conservation
    a_no_phantom: assert property (m_hsk |-> occupancy != 0);
  end

  a_no_overflow: assert property (
    s_hsk |-> occupancy != MAX_PENDING || m_hsk);
  // A stalled output offer must already have accepted input credit, or be a
  // live fall-through of the matching input offer. No READY is required.
  a_no_phantom_offer: assert property (
    m_valid |-> occupancy != 0 || (ALLOW_BYPASS && s_valid));
  // Pure selected-occurrence bookkeeping, sharing the existing stream state.
  // Prove it from the conservation bounds before using it for integrity.
  a_tracker_pending_rank: assert property (
    pending |-> occupancy > rank);
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
  c_stalled_selected_offer: cover property (
    stored_selected_m_offer && !m_hsk);
  c_stalled_exact_selected_offer: cover property (
    selected_m_offer && !m_hsk);
  c_stalled_live_bypass_offer: cover property (
    live_bypass_m_offer && !m_hsk);
  if (MAX_PENDING > 1) begin : g_rank_cover
    c_select_with_rank: cover property (select_now && occupancy != 0);
  end
  c_complete: cover property (completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      selected <= 1'b0;
      pending <= 1'b0;
      completed <= 1'b0;
      watched_data_bit <= 1'b0;
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
        watched_data_bit <= watch_bit < WIDTH ? s_data[watch_bit] : 1'b0;
        age <= '0;
        if (ALLOW_BYPASS && occupancy == 0 && m_hsk) begin
          pending <= 1'b0;
          completed <= 1'b1;
          rank <= '0;
        end else begin
          pending <= 1'b1;
          rank <= occupancy - ((m_hsk && occupancy != 0) ? 1'b1 : 1'b0);
        end
      end else if (pending && m_hsk) begin
        if (rank == 0) begin
          pending <= 1'b0;
          completed <= 1'b1;
        end else begin
          rank <= rank - 1'b1;
        end
      end

      if (pending && ENABLE_PROGRESS && age < MAX_DELAY)
        age <= age + 1'b1;
    end
  end
endmodule
