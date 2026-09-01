// Production transparent ready/valid FIFO checker.  The exact bounded
// reference queue lives under fvip_validation/reference_models.
module fv_fifo_tracker #(
  parameter int WIDTH = 32,
  parameter int MAX_OCCUPANCY = 4,
  parameter bit ALLOW_BYPASS = 1'b0,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 100
) (
  input logic clk,
  input logic rstn,
  input logic [WIDTH-1:0] s_data,
  input logic s_hsk,
  input logic [WIDTH-1:0] m_data,
  input logic m_hsk
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int COUNT_W = (MAX_OCCUPANCY < 2) ? 1 : $clog2(MAX_OCCUPANCY + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);

  // anyseq chooses an occurrence, not a value.  The assumptions permit every
  // input handshake to be chosen and prohibit choosing a non-handshake.
  (* anyseq *) logic select_now;
  logic selected, pending, completed;
  logic [WIDTH-1:0] watched_data;
  logic [COUNT_W-1:0] rank;
  logic [COUNT_W-1:0] occupancy;
  logic [AGE_W-1:0] age;

  s_select_handshake: assume property (select_now |-> s_hsk && !selected);
  s_select_once: assume property (selected |-> !select_now);

  generate if (ALLOW_BYPASS) begin : g_conservation_bypass
    a_no_phantom: assert property (m_hsk |-> occupancy != 0 || s_hsk);
  end else begin : g_conservation_registered
    a_no_phantom: assert property (m_hsk |-> occupancy != 0);
  end endgenerate
  a_no_overflow: assert property (s_hsk |-> occupancy != MAX_OCCUPANCY || m_hsk);
  a_watched_integrity: assert property (pending && m_hsk && rank == 0 |-> m_data == watched_data);
  generate if (ALLOW_BYPASS) begin : g_bypass
    a_selected_bypass: assert property (select_now && occupancy == 0 && m_hsk |-> m_data == s_data);
  end endgenerate

  generate if (ENABLE_PROGRESS) begin : g_progress
    a_watched_progress: assert property (pending |-> age < MAX_DELAY);
  end endgenerate

  c_select: cover property (select_now);
  c_select_behind_data: cover property (select_now && occupancy != 0);
  c_watched_complete: cover property (completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      selected <= 1'b0;
      pending <= 1'b0;
      completed <= 1'b0;
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
        if (occupancy == 0 && m_hsk) begin
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

