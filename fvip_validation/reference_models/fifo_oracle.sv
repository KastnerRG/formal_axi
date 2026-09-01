// Exact bounded ready/valid FIFO reference model.
//
// This is validation-only state used to check the production selected-
// occurrence tracker.  DUT sign-off runs must instantiate fv_fifo_tracker,
// not this shadow queue.
module fv_fifo_oracle #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 2,
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
  localparam int COUNT_W = (DEPTH < 2) ? 1 : $clog2(DEPTH + 1);
  localparam int AGE_W = (MAX_DELAY < 2) ? 1 : $clog2(MAX_DELAY + 1);

  logic [WIDTH-1:0] queue [0:DEPTH-1];
  logic [COUNT_W-1:0] count;
  logic [AGE_W-1:0] oldest_age;

  wire bypass = s_hsk && m_hsk && count == 0;
  wire pop = m_hsk && count != 0;
  wire push = s_hsk && !bypass;

  a_no_phantom: assert property (@(posedge clk) disable iff (!rstn)
    m_hsk |-> count != 0 || s_hsk);
  a_no_overflow: assert property (@(posedge clk) disable iff (!rstn)
    s_hsk |-> count != DEPTH || m_hsk);
  a_head_integrity: assert property (@(posedge clk) disable iff (!rstn)
    m_hsk && count != 0 |-> m_data == queue[0]);
  generate if (ALLOW_BYPASS) begin : g_bypass
    a_bypass_integrity: assert property (@(posedge clk) disable iff (!rstn)
      bypass |-> m_data == s_data);
    c_bypass: cover property (@(posedge clk) disable iff (!rstn) bypass);
  end endgenerate

  c_push: cover property (@(posedge clk) disable iff (!rstn) s_hsk);
  c_pop: cover property (@(posedge clk) disable iff (!rstn) m_hsk);
  c_simultaneous: cover property (@(posedge clk) disable iff (!rstn) s_hsk && m_hsk);
  c_duplicate_payload: cover property (@(posedge clk) disable iff (!rstn)
    count != 0 && s_hsk && s_data == queue[0]);
  c_full: cover property (@(posedge clk) disable iff (!rstn) count == DEPTH);

  generate if (ENABLE_PROGRESS) begin : g_progress
    a_bounded_progress: assert property (@(posedge clk) disable iff (!rstn)
      count != 0 |-> oldest_age < MAX_DELAY);
  end endgenerate

  integer i;
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      count <= '0;
      oldest_age <= '0;
    end else begin
      case ({push, pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase

      if (pop)
        for (i = 0; i < DEPTH-1; i = i + 1)
          queue[i] <= queue[i+1];
      if (push)
        queue[count - (pop ? 1'b1 : 1'b0)] <= s_data;

      if (count == 0 || pop)
        oldest_age <= '0;
      else if (ENABLE_PROGRESS && oldest_age < MAX_DELAY)
        oldest_age <= oldest_age + 1'b1;
    end
  end
endmodule
